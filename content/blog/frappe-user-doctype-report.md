+++
title = "Tracking User DocType Permissions In Frappe"
date = 2023-07-22
published = true
categories = ["python, frappe"]
+++

In a Frappe site with 100s of users and 10s of DocTypes, ensuring everyone has appropriate access levels can quickly get quite tricky. Especially if you have an app with a large number of roles. Frappe's built-in `Role Permission Manager` does not quite cut it as it does not show user to doctype mapping. This short post shows we manage this.

We have a simple SQL query in Metabase that displays all the doctypes a user has access to. We review this about once a week to ensure privileges are not being granted to users who should not really have them.


```sql
SELECT 
    U.User,
    U.Roles,
    GROUP_CONCAT(DISTINCT CASE WHEN DP.`read` = 1 THEN DP.parent 
        ELSE NULL END ORDER BY DP.parent SEPARATOR ', ') 
        AS ReadPermissions,
    GROUP_CONCAT(DISTINCT CASE WHEN DP.`write` = 1 THEN DP.parent 
        ELSE NULL END ORDER BY DP.parent SEPARATOR ', ') 
        AS WritePermissions
FROM (
    SELECT 
      `parent` AS User,
      GROUP_CONCAT(`role` ORDER BY `role` SEPARATOR ', ') AS Roles
    FROM 
      `tabHas Role`
    WHERE parenttype='User'
    GROUP BY 
      `parent`
) AS U
JOIN `tabDocPerm` AS DP ON FIND_IN_SET(DP.role, U.Roles)
GROUP BY 
  U.User
ORDER BY 
  U.User;
```

You can easily adapt this to look for `delete` privileges too. We then use email subscriptions in Metabase to send this off to customer admins to take action as needed. Of course, you can also use Frappe SQL reports to do the same.
