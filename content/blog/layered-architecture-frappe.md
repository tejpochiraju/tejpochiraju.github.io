+++
title = "Layered Architecture With Frappe"
date = 2023-07-21
published = true
categories = ["python, frappe"]
+++

Being different is raison d'etre for web frameworks. And Frappe is more different than most. There was a time when Frappe's [architecture diagram](https://frappeframework.com/docs/v14/user/en/basics/architecture) was one of the first things you saw in the documentation. Today, it's buried a long, long way down in the table of contents.

Frappe's revolutionary concept is the use of _apps_ to organise functionality. Frappe itself is an app and all other apps depend on the Frappe app. A typical deployment or `site` will contain multiple apps that together provide the functionality that the site needs. The most common, and certainly the largest, Frappe app is ERPNext. When you need to provide customer specific ERPNext functionality, you install Frappe, ERPNext and your custom app that depends on these too. The application stack looks like this:

<table style="border: 1px solid black; border-collapse: collapse;">
  <tr>
    <td style="border: 1px solid black;">Custom App</td>
  </tr>
  <tr>
    <td style="border: 1px solid black;">ERPNext</td>
  </tr>
  <tr>
    <td style="border: 1px solid black;">Frappe</td>
  </tr>
</table>


In this stack, Frappe knows nothing about ERPNext or your custom app. ERPnext depends on Frappe but knows nothing about your custom app. Your custom app depends on Frappe and ERPNext. 

This is how I have been building Frappe apps, with or without ERPNext, for 5 years now. And [until yesterday](https://blog.europython.eu/kraken-technologies-how-we-organize-our-very-large-pythonmonolith/), I didn't realise that this follows the best practices of layered architecture. Frappe's architecture documentation does not mention layering once. However, on reflection, I think this architecture is what makes working in Frappe so productive.

> And, very, occasionally hairy when something you don't control shifts from underneath you.


## Inversion Of Control

Layering is not all rosy though. As the Kraken Tech blog above notes, layering also induces incentives to make the top layers heavier. This obviously reduces code reuse. The approach they suggest to counteract this tendency is to use [Inversion Of Control](https://seddonym.me/2019/04/15/inversion-of-control/). Another phrase that I had heard in passing but never explored or understood. 

And once you read about it, you realise that this is implemented in Frappe too and we use it on a daily basis. [`hooks`](https://frappeframework.com/docs/v14/user/en/python-api/hooks) are essentially Frappe's way to provide inversion of control. 

{% mermaid() %}
graph TD;
    CustomApp-- depends -->Frappe;
    Frappe-. hooks .->CustomApp;
{% end %}

Now, I realise that most frameworks have event hooks but few have it for the number of events that Frappe does. Event hooks allow for some pretty great customisability. Especially when paired with overrides for DocType classes and Form scripts.

> We use overrides for classes and scripts very sparingly because it's easy to lose track of where some custom behaviour is coming from. Instead, we abstract some of these use cases into separate DocTypes, e.g. a `User Profile` linked to each `User`.


### Implementing Your Own Hooks

For one of our applications, we wanted to provide a way for customer specific functionality to be added. Specifically, in this case, we needed to add custom validation to some APIs. Digging in the Frappe code base, we found `frappe.get_attr`. This function converts a dotted string path into a module or function that you can then execute. Here's how you use it.

#### Add a place to define hooks

![Event Hooks](/images/warehouse_hooks.png)


#### Use the hook in your API function

```python
@frappe.whitelist()
def record_events(**kwargs):
    try:
        prefix = kwargs.get('activity').lower().replace(" ", "_")
        hook = frappe.db.get_single_value(
            "IoTReady Traceability Settings", f"{prefix}_event_hook"
        )
        hook_result = None
        if hook:
            hook_result = frappe.get_attr(hook)(kwargs)
        result = some_function(kwargs)
        if hook_result:
            result.update(hook_result)
    except Exception as e:
        print("Exception in record_events: ", str(e))
        result = {"success": False, "message": str(e)}
    return result
```

Now, obviously, you have to implement the hook somewhere. We usually do this in a customer-specific application, `iotready_godesi` in the screenshot above.


### Pros & Cons Of Inversion Of Control

- **+** Using inversion of control allows you to use core APIs (and UIs) as they are and build/test your custom functionality independently.
- **+** This allows for significant code reuse and keeps customer-specific code out of your core functionality.
- **-** It does however mean that some functionality is harder to build and may require future, unforeseen requirements to the core functionality. 
- **-** All changes to the core have to be carefully evaluated to avoid impacting other customers.


## Conclusions

Layering and inversion of control are both very useful architectural principles for structuring code - especially when you are in a B2B space like us and often need customer-specific functionality. 

Our code base is small enough that making changes to follow these principles is not too difficult. Frappe encourages these architectures so we are on solid ground already. 

For the reasons listed above vis-a-vis inversion, we now lean towards using the layered approach as a default and use inversion of control as a pragmatic escape hatch. This means, for instance, that we are evaluating a small API rewrite so that the `record_events` API is exposed via the customer app rather than our core traceability app. More when we complete our evaluation.


