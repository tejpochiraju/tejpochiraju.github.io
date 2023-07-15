+++
title = "Realtime Webviews With Frappe"
date = 2023-07-15
categories = "python, frappe, vuejs, realtime"
published = true
+++

From [undocumented & underused](/blog/frappe-deferred-bulk/) to something much more 
prevalent in the Frappe codebase.

It takes less than 10 lines of code to add reliable, realtime capabilities to any Frappe application.
Capabilities that let you do something like this:

![Realtime count](/images/realtime_count.gif) 

## Code

### Client

Frappe ships with VueJS 2.0 as part of its web bundle, so we are going to use that to keep
the code declarative. And because, Vue is pre-bundled, we can add it to any page - even one 
we create using Desk (/app/web-page).


```javascript
<div id="app" class="container m-4">
    <p>Count: {{ count }}</p>
</div>

<script>
    frappe.ready(() => {
        new Vue({
            el: "#app",
            data: {
                count: 0
            },
            mounted() {
                setTimeout(() => {
                    frappe.realtime.on("count", (data) => {
                        this.count = data.count;
                    })
                }, 3000)
            }
        })
    });
</script>
```

#### Notes
- Vue is not needed for any of this. You can do this with vanilla JS as long as you have 
Frappe's JS bundle available (included in the default `web.html` template).
- I had issues establishing the realtime connection without waiting for a few seconds, 
hence the `setTimeout`.

### Server

Frappe bundles `socket.io` on the server side to handle realtime communications over websockets.
As a developer, you interact with the [simple Python API](https://frappeframework.com/docs/v14/user/en/api/realtime).

In our example above, all we did to send updates was:

```python
for i in range(100):
    frappe.publish_realtime(event="count", user="Administrator", message={"count": i})
    sleep(1)
```

## How does it work?

The Python API is fairly simple and contained entirely in [`realtime.py`](https://github.com/frappe/frappe/blob/develop/frappe/realtime.py).
This file is worth a read. The Python side communicates with the Socket.IO server using its [Redis Adapter](https://socket.io/docs/v4/redis-adapter/).

In order to route the messages, Frappe uses "rooms" which are specific to tasks/documents or users.
There's even a site wide broadcast room. At the Redis level, the `room` is just a key in the JSON
structure that is sent to `events` PubSub channel (see `emit_via_redis` inside `realtime.py`).

Once an event has been published to Redis, the Socket.IO adapter picks it up and broadcasts it 
to subscribed clients. Socket.IO uses Websockets for client communication with a fallback to HTTP 
longpolling. Socket.IO's [documentation](https://socket.io/docs/v4/how-it-works/) is pretty 
fantastic at explaining the internals.

![Socket.IO Redis](/images/socketio_redis.png)

Finally, to make it all work, Frappe's web bundle includes a [Socket.IO client](https://github.com/frappe/frappe/blob/version-14/socketio.js)
that handles authentication, authorization, reconnects, subscriptions and publishing. 
Yes, clients can send messages to the server too. That's for a later post.

> Btw, Frappe's realtime code is getting a bit of a rewrite in the `develop` branch [as we speak](https://github.com/frappe/frappe/tree/develop/realtime).


## What can you use it for?

Frappe uses it for presence (showing who else is viewing a document), updating list views and 
showing progress when uploading files or importing data.

[We](https://iotready.co) use it for sending asynchronous realtime updates to our webviews, even those embedded 
in our mobile apps. We have long planned to migrate our workflow apps over to Phoenix but that's 
a lot of work and these realtime capabilisties significantly reduce the value of doing that.

That said, Phoenix LiveView is an absolute joy to work with and gives you much simpler ways
to architect your application and reason about the realtime pieces.


