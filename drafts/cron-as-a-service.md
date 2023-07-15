I (think I) recall reading somewhere recently about a cron web service, i.e. something that triggers a
webhook on a predefined schedule. In any case, a service like this came to mind again when thinking of how to trigger a Python API
inserted into Frappe using the Desk dashboard. 

This should be relatively simple to build using a robust job management system such as Oban in Elixir. So, that's 
what we will attempt to do here.
