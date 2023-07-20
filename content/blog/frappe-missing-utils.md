+++
title = "Utility Functions You Didn't Know You Needed"
date = 2023-07-20
published = true
categories = ["python, frappe"]
+++

This is intended as a living post that I will update as I find/write utility functions that I commonly reach out for.

> Last updated: 2023-07-20


## Frappe Specific

### Enqueue As Admin

This is useful for running side-effects that would otherwise need you to grant someone a lot of `DocType` permissions. It is important that the side-effects are relatively benign as this grants the caller Admin privileges for your function.

```python
import frappe
from frappe.utils.background_jobs import (
    get_queue,
    execute_job,
    RQ_JOB_FAILURE_TTL,
    RQ_RESULTS_TTL,
)
from frappe.utils import cstr

def enqueue_as_admin(method, **kwargs, job_name=None, queue_name='long', timeout=3600):
    queue_args = {
        "site": frappe.local.site,
        "user": "Administrator",
        "method": method,
        "event": None,
        "job_name": job_name or cstr(method),
        "is_async": True,
        "kwargs": kwargs,
    }
    q = get_queue(queue_name)
    j = q.enqueue_call(
        execute_job,
        timeout=timeout,
        kwargs=queue_args,
        at_front=False,
        failure_ttl=frappe.conf.get("rq_job_failure_ttl") or RQ_JOB_FAILURE_TTL,
        result_ttl=frappe.conf.get("rq_results_ttl") or RQ_RESULTS_TTL,
    )

```


### Get File Path
Converts a `file_url`, e.g. from an `Attach` field in a document, into a path that can be passed to `open`.

```python
import frappe
import os

def get_file_path(file_url):
    if not file_url:
        return None
    site_dir = frappe.get_site_path()
    if file_url.startswith("/"):
        file_url = file_url[1:]
    return os.path.join(site_dir, file_url)

```

## DateTime

### Date To Week Of Month
Given a date, returns a number in the range 1-5.

```python
from datetime import timedelta

def week_of_month(date):
    month = date.month
    week = 0
    while date.month == month:
        week += 1
        date -= timedelta(days=7)
    if week > 4:
        week = 4
    return week

```

### First Day Of The Week
Given a month, year and week within the month, returns the day (number) of the first day of the week.

```python
from datetime import datetime, timedelta

def get_first_day_of_week(year, month, week):
    """Returns the first day of the week."""
    date = datetime.strptime("{}-{}-1".format(year, month), "%Y-%m-%d")
    first_day_of_week = date + timedelta(days=(week - 1) * 7)
    return first_day_of_week

```

### Multi-Format Date/Time Parser
I have many variants of this parser which handle different kinds of `datetime` formats and either return `None` or raise an error as needed in that context.

```python
from datetime import datetime

def parse_date(row_date):
    formats = [
        "%d-%m-%Y",
        "%Y-%m-%d",
        "%d/%m/%Y",
    ]
    for format in formats:
        try:
            return datetime.strptime(row_date, format).date()
        except:
            pass
    raise ValueError("Invalid date format for Date", row_date)
```

## General Python

### Random String Generator
There's also `frappe.generate_hash` that's a bit more opinionated. This function allows you to specify the characters to pick from. I use this to generate numeric OTPs by calling `random_string_generator(4, string.digits)`

```python
import random

def random_string_generator(str_size, allowed_chars):
    return "".join(random.choice(allowed_chars) for x in range(str_size))

```

### JSON Serialiser For Datetime Values
`json.dumps` fails on dictionaries with `datetime` values. This fixes it. As needed, I will sometimes add additional handlers into this function. See also `frappe.as_json`. 

```python
def date_json_serial(obj):
    if isinstance(obj, (datetime, date)):
        return obj.date().isoformat()
    raise TypeError("Type %s not serializable" % type(obj))
```

### Round As Humans Understand It
`math.round` has some weird behaviour. This function implements `round` the way you and I understand it.

```python
def normal_round(num, ndigits=0):
    """
    Rounds a float to the specified number of decimal places.
    num: the value to round
    ndigits: the number of digits to round to
    From: https://medium.com/thefloatingpoint/pythons-round-function-doesn-t-do-what-you-think-71765cfa86a8
    """
    if ndigits == 0:
        return int(num + 0.5)
    else:
        digit_value = 10**ndigits
        return int(num * digit_value + 0.5) / digit_value

```

### Dictionary To Hashable Key
Dictionary keys do not need to be strings - they can be lists, tuples etc. This is incredibly useful to track groups by categories. If you are currently creating keys that look like `f"{category_1}-{category_2}"`, you could be doing this: `(category_1, category_2)`. 
But can you use a dictionary as a key for another dictionary? No. Think that's crazy? Maybe, but here's how you would do it - by converting the dictionary into a tuple of key, value pairs.

```python
def dict_to_hashable_key(d):
    def to_hashable(value):
        if isinstance(value, list):
            return tuple(to_hashable(item) for item in value)
        return value

    return tuple(sorted((k, to_hashable(v)) for k, v in d.items()))
```

