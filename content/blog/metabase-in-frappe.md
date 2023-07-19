+++
title = "Embedding Metabase Dashboards In Frappe"
date = 2023-07-19
published = true
categories = ["python, frappe, metabase, visualisation"]
+++

Since we collect a lot of operational data, it's inevitable that we do a lot of analysis and visualisation too. Our preferred tool for such analyses is [Metabase](https://www.metabase.com/).

A typical IoTReady workflow solution, e.g. for Warehouse Traceability, works as described below:

- Desk-based staff log into our Frappe applications and modify configuration data (`Supplier`, `SKU`...)
- Warehouse floor staff use our hardware and mobile applications to carry out operations.
- Operational data flows into our events infrastructure, [Bodh](https://bodh.iotready.co).
- Validations are carried out against the customer's configuration data using a rules engine.
- Metabase is used to make sense of the large volume of data by carrying out aggregations and comparisons (e.g. `Transferred Out` vs `Transferred In`).

While we could leave it at this, asking users to go to a separate Metabase instance just for the couple of reports that role might need seems unnecessary. Besides, filtering questions and dashboards inside Metabase based on roles in Frappe would need mapping of all the roles and all the users.

![Metabase In Frappe](/images/metabase_frappe.png)

## `<iframe>`s & Filters

There's a simpler way to approach this:
- create a Metabase dashboard with the appropriate filters and enable them for embedding.
- embed the dashboard in Frappe using an `<iframe>`. 
- use Frappe roles and Metabase dashboard filters to show the users only what they need/are allowed to see.
- abstract this pattern to embed multiple dashboards.

The Metabase setup is quite simple and [well documented](https://www.metabase.com/docs/latest/embedding/introduction). The important things to note are the `Editable` filters and enabling embeds in your global configuration. Once you have done this, you need to note your dashboard ID (shown in the URL as well as the `Code` tab).

![Metabase Dashboard Setup](/images/metabase_embed.png)

On the Frappe side, we create a `Page` that calls some Python code upon loading.

```js
// Page
frappe.pages['warehouse-summary'].on_page_load = function (wrapper) {
	frappe.call({
		method: "app.utils.get_warehouse_dashboard",
		type: "GET",
		args: {},
		callback: (r) => {
			// console.log("result", r);
			if (r.exc) {
				console.error("error", r.exc);
			} else {
				$(wrapper).html(r.message);
			}
		},
		freeze: false,
		freeze_message: "",
		async: true,
	});
}
```

The Python function (`get_warehouse_dashboard` in this case) is page specific. This function's job is map to the right dashboard, generate the filters and call a more general function `get_metabase_dashboard`. This function generates the JWT token needed to load a dashboard from our Metabase instance, creates a custom `<iframe>` url and renders some HTML with this `<iframe>`.

```python
# Controller code
import frappe
import jwt
import time

@frappe.whitelist()
def get_warehouse_dashboard():
    dashboard_id = 3
    roles = frappe.get_roles(frappe.session.user)
    if (
        "BIG BOSS" in roles
    ):
        params = {}
    else:
        # get_list filters Warehouse by user specific permissions.
        warehouses = [r[0] for r in frappe.get_list("Warehouse", as_list=True)]
        params = {"warehouse": warehouses}
    return get_metabase_dashboard(dashboard_id, params)

def get_metabase_dashboard(dashboard_id: int, params={}):
    METABASE_SITE_URL = frappe.conf["metabase_site_url"]
    METABASE_SECRET_KEY = frappe.conf["metabase_secret_key"]
    payload = {
        "resource": {"dashboard": dashboard_id},
        "params": params,
        "exp": round(time.time()) + (60 * 10),  # 10 minute expiration
    }
    token = jwt.encode(payload, METABASE_SECRET_KEY, algorithm="HS256")

    iframeUrl = (
        METABASE_SITE_URL + "/embed/dashboard/" + token + "#bordered=false&titled=false"
    )
    html = frappe.render_template(
        "templates/includes/metabase_dashboard.html",
        {"iframeUrl": iframeUrl, "title": "Dashboard"},
    )
    return html

```
And here's the `HTML` template. The embedded script makes the iframe responsive.

```html
<!-- template -->
<iframe src="{{iframeUrl}}" style="width: 100%;" frameborder="0" width="1280" height="800" allowtransparency
    id="Iframe"></iframe>

<script>
    // Selecting the iframe element
    var frame = document.getElementById("Iframe");
    // Adjusting the iframe height onload event
    frame.onload = function ()
    // function execute while load the iframe
    {
        // set the height of the iframe as 
        // the height of the iframe content
        frame.style.height =
            frame.contentWindow.document.body.scrollHeight + 'px';
        // set the width of the iframe as the 
        // width of the iframe content
        frame.style.width =
            frame.contentWindow.document.body.scrollWidth + 'px';
    }
</script>
```

### Notes

- This works well in a desktop layout but Metabase dashboards are not a great fit for mobile (even with the responsive code above).
- Test your filters thoroughly - especially if you are at risk of leaking sensitive information, e.g. in a multi-tenant environment.
- If exposing the Metabase instance directly to customers, it's nicer to [hide all tables by default](https://github.com/metabase/metabase/issues/2146#issue-140719155) and only enable the ones you want to showcase.
