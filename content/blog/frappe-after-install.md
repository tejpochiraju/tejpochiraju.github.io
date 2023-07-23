+++
title = "After Install Cleanup For Frappe Apps"
date = 2023-07-23
published = true
categories = ["python, frappe"]
+++

Frappe ships with a number of workspaces and roles out of the box. These workspaces have short cuts for a number of core system functionality including managing users and integrations. However, we almost never use these shortcuts - instead preferring the search bar. 

The roles are more problematic as they include a number of roles that have no business being in a core web framework, e.g. "Purchase User". These are clearly an ERPNext legacy. They can lead to confusion when creating your own roles later. As a rule, we don't use any of these roles when building our apps to avoid leaking privileges if we install any other Frappe app or install our app alongside ERPNext.

To simplify matters, we use a [post-install hook](https://frappeframework.com/docs/v14/user/en/python-api/hooks#install-hooks) in our apps to clean up these workspaces and roles. Here's how. 

### `hooks.py`

```python
after_install = "iotready_multitenancy.install.after_install"
```

### `install.py`

```python
import frappe

def core_workspaces():
    """
    Returns a list of core workspaces.
    List accurate as of v14 - commit hash: aba05da
    """
    return (
        "Tools",
        "Users",
        "Website",
        "Integrations",
        "Customization",
        "Settings",
        "Build",
    )

def hide_core_workspaces():
    """
    Hide core workspaces from the workspace list.
    """
    sql = """
    UPDATE `tabWorkspace` SET is_hidden = 1 WHERE name IN ({workspaces});
    """
    frappe.db.sql(
        sql.format(workspaces=", ".join(["'{}'".format(d) for d in core_workspaces()]))
    )
    frappe.db.commit()

def core_roles():
    """
    Returns a list of core roles.
    List accurate as of v14 - commit hash: aba05da
    """
    return [
        "Accounts Manager",
        "Accounts User",
        "Administrator",
        "All",
        "Blogger",
        "Dashboard Manager",
        "Guest",
        "Inbox User",
        "Knowledge Base Contributor",
        "Knowledge Base Editor",
        "Maintenance Manager",
        "Maintenance User",
        "Newsletter Manager",
        "Prepared Report User",
        "Purchase Manager",
        "Purchase Master Manager",
        "Purchase User",
        "Report Manager",
        "Sales Manager",
        "Sales Master Manager",
        "Sales User",
        "Script Manager",
        "System Manager",
        "Translator",
        "Website Manager",
        "Workspace Manager",
    ]

def protected_roles():
    """
    These roles should not be given to customer users.
    """
    roles = core_roles()
    roles.remove("All")
    roles.remove("Guest")
    return roles

def disable_unused_roles():
    roles = protected_roles()
    roles.remove("Administrator")
    roles.remove("System Manager")
    roles.remove("Workspace Manager")
    roles.remove("Script Manager")
    sql = """
    UPDATE `tabRole` SET disabled = 1 WHERE name IN ({roles});
    """
    frappe.db.sql(sql.format(roles=", ".join(["'{}'".format(d) for d in roles])))
    frappe.db.commit()

def allow_reading_roles():
    """
    Allows Organisation Admin to read roles.
    """
    doc = frappe.new_doc("Custom DocPerm")
    doc.parent = "Role"
    doc.role = "Organisation Admin"
    doc.read = 1
    doc.save()
    frappe.db.commit()

def after_install():
    hide_core_workspaces()
    disable_unused_roles()
    allow_reading_roles()

```

With these few lines of code, we ensure that our workspaces and roles start clean. In a future post, I will share the tasks we use to keep them clean.
