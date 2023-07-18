+++
title = "ORM Speed Up In Frappe"
date = 2023-07-18
published = true
categories = ["python, frappe, cache"]
+++

ORMs can [be slow](https://stackoverflow.com/questions/699792/is-orm-slow-does-it-matter).
However, they are also very useful and central to Frappe's entire metadata and document 
centric model.

Frappe's ORM can trigger validations and all kinds of side-effects via document hooks. Like it, or not, these hooks are how one writes Frappe code. So, the ORM is critical on the write-path, if (far) less efficient than raw SQL writes. We have previously explored this topic for [bulk writes](/blog/frappe-deferred-bulk/).

Some of our apps have read heavy APIs where a number of documents are read during a single API transaction. Until recently we had no choice but to choose one of the following:

- Use `frappe.get_doc` and accept the performance penalty, 
- Write raw SQL queries and combine multiple reads into a single DB transaction,
- Roll our own caching and carefully manage invalidations.

## Brave new world

However, I recently discovered `frappe.get_cached_doc` and it's essentially a free performance upgrade. The [documentation](https://frappeframework.com/docs/v14/user/en/guides/caching#cached-documents) is pretty straightforward:

- the return value of `get_cached_doc` is equivalent to the return value of `get_doc`
- the cache is updated any time the ORM is used to update the document (`doc.save` or `frappe.db.set_value`)
    - Raw DB updates and `doc.db_set` do not update the cache. This does mean our `bulk_insert` method does _not_ update the cache. Thankfully, there's `frappe.clear_document_cache(doctype, name)`

## Performance upgrades

What does this mean in terms of performance? A cool **10000x+** increase in read throughput. See the code below for my simplistic benchmark.

```python

from timeit import timeit

def load_doc():
    return frappe.get_doc(doctype, docname)

def load_cached_doc():
    return frappe.get_cached_doc(doctype, docname)

print(timeit(load_doc, number=1000))
# 17.63


print(timeit(load_cached_doc, number=10000000))
# 13.00

```

Sure, caching documents needs more RAM. But RAM is [dirt cheap](https://www.e2enetworks.com/pricing#High-Memory-Cloud) these days, so go ahead and replace `frappe.get_doc` with `frappe.get_cached_doc` in your performance critical paths and enjoy an immediate boost to API responsiveness.


