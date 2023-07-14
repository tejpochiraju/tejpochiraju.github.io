+++
title = "Deferred Bulk Inserts In Frappe"
date = 2023-07-14
categories = "python, frappe, db"
published = true
+++


One of our upcoming SaaS products handles delivery payout calculations for ecommerce companies.
Here, we accept bulk imports of trip and order data for the previous day and then calculate payouts
using fairly complex, dark-store specific rate cards. These imports are often multiple files 
of 100K+ records. Since these files are logically grouped together, we don't 
use Frappe's Data Import UI. And since the files are uploaded and updated by end users, we don't
use `bench import-csv` either. 

> Data Import is implemented as a wrapper for _row by row_ insert/update.

When dealing with 100s of thousands of rows each day, row by row updates and inserts are not
an option - these just take too long (think hours). So, imagine my surprise when ChatGPT suggested
I try out `frappe.db.bulk_insert`. At first, I assumed GPT was up to its hallucinatory tricks again
but I decided to see if such a function existed and [what do you know](https://github.com/frappe/frappe/blob/develop/frappe/database/database.py)!

## Of Undocumented Needles In Haystacks

Frappe has a [built-in ORM](https://frappeframework.com/docs/v14/user/en/api/document) 
that serves us well for most of the common use cases. There are also a few extras that 
are not as commonly used in the Frappe or ERPNext code bases and perhaps not as familiar 
to developers:

- [Query builder](https://frappeframework.com/docs/v14/user/en/api/query-builder)
built on top of Pypika - useful for replacing SQL queries with a more Pythonic API
- [Deferred Inserts](https://github.com/frappe/frappe/blob/develop/frappe/deferred_insert.py) - 
this uses Redis as an aggregation layer and flushes writes to the DB using an hourly task.
- [Bulk Inserts](https://github.com/frappe/frappe/blob/develop/frappe/database/database.py) - 
this function is used _once_ outside tests in the entire Frappe code base and that too inside a patch 
for v12. And not at all inside ERPNext.

ChatGPT found _this_ function. I doubt I ever would have.

## 75 Lines Of Python

My current solution for handling the file imports consists of combining `deferred_insert` and `bulk_insert`.
Here's the workflow before we dive into the code:

1. User attaches 2-3 bulk files to a custom doctype (e.g. `Trip Report`).
2. Using document hooks we parse the files row by row to look for validation errors.
3. We create (in-memory) instances of the doctype we are importing (e.g. `Trip`).
4. We serialise these documents and store them in a Redis list.
5. Once completely parsed, we retrieve the documents from Redis and bulk write them 
to the DB in batches.

Steps 1 - 3 are trivial and common enough that we can skip those. 
To handle 4 and 5, I have a DB helper module adapted from the `deferred_insert` module linked above.

```python
# db.py

queue_prefix = "some_prefix_"


def get_key_name(key: str) -> str:
    return cstr(key).split("|")[1]


def deferred_insert(doc):
    """
    Converts a Frappe document to JSON and stores it in a Redis list.
    """
    doctype = doc.doctype
    docname = doc.name
    if not (doctype and docname):
        frappe.throw("Doctype and Docname are required")
    redis_key = f"{queue_prefix}{doctype}"
    d = doc.as_dict()
    skip = ["docstatus", "doctype", "idx"]
    for key in list(d.keys()):
        if key.startswith('_'):
            d.pop(key)
        if key in skip:
            d.pop(key)
    frappe.cache().rpush(redis_key, frappe.as_json(d))


def bulk_insert(doctype):
    """
    Retrieves JSON documents from a Redis list and bulk inserts in the DB in batches.
    """
    redis_key = f"{queue_prefix}{doctype}"
    queue_keys = frappe.cache().get_keys(redis_key)
    record_count = 0
    unique_names = set()
    records = []
    for key in queue_keys:
        queue_key = get_key_name(key)
        while frappe.cache().llen(queue_key) > 0:
            record = frappe.cache().lpop(queue_key)
            record = json.loads(record.decode("utf-8"))
            if isinstance(record, dict):
                record_count += 1
                if record['name'] in unique_names:
                    continue
                unique_names.add(record['name'])
                records.append(record)
            else:
                print("Invalid record")
    if records:
        for batch in create_batch(records, 1000):
            fields = list(batch[0].keys())
            values = (tuple(record.values()) for record in batch)
            frappe.db.bulk_insert(doctype, fields, values)
    frappe.db.commit()
    print(f"Inserted {record_count} records")
    return record_count


def clear_queue(doctype):
    """
    Clear the queue in case we are reprocessing the same import file.
    """
    redis_key = f"{queue_prefix}{doctype}"
    frappe.cache().delete_keys(redis_key)


def bulk_delete(doctype, docnames):
    """
    Delete records in bulk. This is a wrapper around frappe.db.sql
    docnames is a list of names
    """
    if not doctype or not docnames:
        return
    placeholders = ', '.join(['%s'] * len(docnames))
    sql = f"""DELETE FROM `tab{doctype}` WHERE name IN ({placeholders})"""
    frappe.db.sql(sql, values=docnames)
    frappe.db.commit()
    print(f"Deleted {len(docnames)} records")
    return len(docnames)

```

```python

# usage
doctype = "Some DocType"

for row in large_file:
    doc = frappe.new_doc(doctype)
    doc.attribute = row["some_value"]
    doc.name = "some_name" # this is necessary as bulk_insert does not trigger autoname
    doc.creation = datetime.now()
    doc.modified = datetime.now()
    doc.owner = frappe.session.user
    doc.modified_by = frappe.session.user

    db.deferred_insert(doc)

db.bulk_insert(doctype)

```

### How much time does this save? 

> For every 150K records, this reduces the import time from about 3000 seconds to ~120 seconds.

## Notes & Improvements

- `deferred_insert` is not necessary here. You could aggregate the records in a normal Python
list and pass them to `bulk_insert` directly. I prefer this queue pattern as it allows me to decouple
DB inserts completely if I want to.
- The built-in `frappe.db.bulk_insert` does not support conflicts/updates. I am porting some of my 
SQL code that handles this over to the Query builder. Will post once completed.
