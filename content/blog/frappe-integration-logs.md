+++
title = "External API Integration Logs For Frappe Apps"
date = 2023-07-25
published = true
categories = ["python, frappe"]
+++

Very frequently, we need to integrate our Frappe apps with customer/third-party applications. This could be a warehouse management system, an ERP or an employee vetting SaaS. 

With `requests`, secret storage using `frappe.conf` and `hooks`, tasks like this are relatively straightforward. Having persistent logs for such integrations is key to quickly identifying and patching errors.

By now you know the theme. Yes, Frappe has a built-in `DocType` for such logs. And yes, it's only documented in the source code.  

### Meet `Integration Request`

Frappe even ships with a helper function to create these logs - `frappe.integrations.utils.create_request_log`. This function is used a few times in the ERPNext and `Payments` codebases to handle payment provider integrations. Here's how it works. 

#### `create_request_log` 

The function uses kwargs and default values to stay agnostic of the actual API request.

```python
def create_request_log(
	data,
	integration_type=None,
	service_name=None,
	name=None,
	error=None,
	request_headers=None,
	output=None,
	**kwargs,
):
	"""
	DEPRECATED: The parameter integration_type will be removed in the next major release.
	Use is_remote_request instead.
	"""
	if integration_type == "Remote":
		kwargs["is_remote_request"] = 1

	elif integration_type == "Subscription Notification":
		kwargs["request_description"] = integration_type

	reference_doctype = reference_docname = None
	if "reference_doctype" not in kwargs:
		if isinstance(data, str):
			data = json.loads(data)

		reference_doctype = data.get("reference_doctype")
		reference_docname = data.get("reference_docname")

	integration_request = frappe.get_doc(
		{
			"doctype": "Integration Request",
			"integration_request_service": service_name,
			"request_headers": get_json(request_headers),
			"data": get_json(data),
			"output": get_json(output),
			"error": get_json(error),
			"reference_doctype": reference_doctype,
			"reference_docname": reference_docname,
			**kwargs,
		}
	)

	if name:
		integration_request.flags._name = name

	integration_request.insert(ignore_permissions=True)
	frappe.db.commit()

	return integration_request
```


#### Usage

```python
import requests
import json
from frappe.integrations.utils import create_request_log
from frappe.model.document import Document

class CustomDoctype(Document):
    def some_hook(self)
        response = requests.post(some_url, data=json.dumps(some_data_dict), headers=some_header_dict)
        kwargs = {
            "url": some_url, 
            "is_remote_request": 1, 
            "reference_doctype": self.doctype,
            "reference_docname": self.name,
            "status_code": response.status_code,
            "status": "Completed" if response.status_code == 200 else "Failed"
        }
        output = error = None 
        if response.status_code == 200:
            output = response.json()
        else:
            error = response.text
        create_request_log(data=some_data_dict, service_name="some_service", output=output, error=error, request_headers=some_header_dict, **kwargs)

```


### We Can Do Better

`create_request_log` works fine. However, given its synchronous nature, usage adds a time delay. We can instead use our [bulk `deferred_insert`](/blog/frappe-deferred-bulk/) to reduce delays. While we are doing that, let's all simplify the function signature.


```python
import requests
import json
import frappe
from datetime import datetime
from custom_app.db import deferred_insert
from frappe.model.document import Document

# I usually keep this function in a `utils.py` and call `bulk_insert('Integration Request')` in a minutely task
def insert_log(response, doc=None):
    """
    `doc` is a Frappe document.
    `response` is a `requests` response.
    """
    log = frappe.new_doc("Integration Request")
    log.name = frappe.generate_hash(length=10)
    log.creation = datetime.now()
    log.modified = datetime.now()
    log.owner = frappe.session.user
    log.modified_by = frappe.session.user
    log.url = response.url
    log.reference_doctype = doc and doc.doctype
    log.reference_docname = doc and doc.name
    log.request_headers = response.request.headers
    log.data = response.request.body
    log.status_code = response.status_code
    if log.status_code == 200:
        log.status = "Completed"
        log.output = response.text
    else:
        log.status = "Failed"
        log.error = response.text
    deferred_insert(log)


class CustomDoctype(Document):
    def some_hook(self)
        response = requests.post(some_url, data=json.dumps(some_data_dict), headers=some_header_dict)
        insert_log(response, self)

```

### Notes

- It's critical to redact sensitive information, if any, from `response.request.body` and `response.text`
- If you are making a large number of requests, you may want to prune these logs every so often - especially if the `data` or the response are large.
