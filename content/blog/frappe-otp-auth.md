+++
title = "Phone and OTP Auth For Frappe"
date = 2023-07-17
published = true
categories = ["python, frappe, otp, authentication"]
+++

A lot of our end-users belong to the non-email majority. For such users, we have long preferred
using phone and OTP authentication as a reliable alternative. Here's a simple module that implements 
this using MSG91. 

> Note that Frappe supports 2-Factor authentication using a phone and OTP. Here, we are talking about 
phone and OTP as the first and only factor.

## Setup 

In order to use this code, we need to:

- Map the phone number to each user - there's a `mobile_no` field in the `User` doctype.
- Configure our SMS provider's credentials and template ID in `site_config.json` as per the keys in the code.


```python
import frappe
import string
import random
import requests

REDIS_PREFIX = "otp"

def random_string_generator(str_size, allowed_chars):
    return "".join(random.choice(allowed_chars) for x in range(str_size))


def send_sms(phone, otp, domain):
    # Strip out + when sending SMS
    phone = phone.replace("+", "")
    url = "https://control.msg91.com/api/v5/flow/"

    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "authkey": frappe.conf["msg91_authkey"],
    }
    payload = {
        "template_id": frappe.conf["msg91_template_id"],
        "sender": frappe.conf.get("msg91_sender_id") or "IoTRDY",
        "short_url": "0",
        "mobiles": phone,
        "var1": domain,
        "var2": otp,
    }
    response = requests.post(url, json=payload, headers=headers)
    try:
        return response.json()
    except Exception as e:
        return {"error": str(e)}


def generate_otp_for_phone(phone, domain):
    payload = {
        "success": False,
        "message": None,
    }
    if phone[0] != "+":
        phone = f"+91{phone}"  # Set India as default
    otp = random_string_generator(4, string.digits)
    frappe.cache().set(f"{REDIS_PREFIX}:{phone}", otp, ex=300)
    try:
        send_sms(phone=phone, otp=otp, domain=domain)
        payload["success"] = True
        payload["message"] = f"OTP sent by SMS sent to {phone}"
    except Exception as e:
        print(str(e))
        payload["message"] = str(e)
    return payload


def verify_otp_for_phone(phone, otp):
    payload = {
        "success": False,
        "message": None,
    }
    if phone[0] != "+":
        phone = f"+91{phone}"  # Set India as default
    key = f"{REDIS_PREFIX}:{phone}"
    stored_otp = frappe.cache().get(key).decode("utf-8")
    if not stored_otp == otp:
        payload["message"] = "Incorrect OTP."
        return payload

    try:
        user = frappe.db.get("User", {"mobile_no": phone})
    except Exception as e:
        payload["message"] = "User not found."
        return payload

    # Delete stored OTP
    frappe.cache().delete_key(key)

    # Now log in as user
    from frappe.auth import CookieManager, LoginManager

    frappe.utils.set_request(path="/")
    frappe.local.cookie_manager = CookieManager()
    frappe.local.login_manager = LoginManager()
    return frappe.local.login_manager.login_as(user.name)

```

We then expose these functions via `api.py` so they can be called from our mobile apps:

```python
import frappe
from iotready_otp.utils import generate_otp_for_phone, verify_otp_for_phone


@frappe.whitelist(allow_guest=True)
def generate_otp(phone):
    return generate_otp_for_phone(phone)


@frappe.whitelist(allow_guest=True)
def verify_otp(phone, otp):
    return verify_otp_for_phone(phone, otp)

```


### Notes

- You don't have to pass the `domain` parameter and could instead configure this per site in `site_config.json`
- You could modify Frappe's response status code and throw a `403` in case of incorrect OTPs. 


