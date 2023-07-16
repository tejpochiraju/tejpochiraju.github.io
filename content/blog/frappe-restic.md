+++
title = "Incremental Backups For Frappe Using Restic"
date = 2023-07-16
categories = "python, frappe, backups, restic"
published = true
+++

Built-in [backup and restore](https://frappeframework.com/docs/v14/user/en/bench/reference/backup)
functionality is definitely one of Frappe's nicer features. Having used `bench restore` to move
servers and, once, recover from a failed server I can vouch for its efficacy.

A Frappe site is fully backed up if you have backups for the application code, DB, files and the `site_config.json`.
All our application code is on Github and a couple of computers so we will focus on the others.

The default `bench backup` creates snapshot `tar.gz` files for the DB, public files and private files. Based on the 
selected routine, it will also take snapshots of the `site_config.json` file. You can even configure 
Frappe to store the backups on AWS S3 - this works really well and will email you if the backup fails for some reason.

> `site_config.json` is quite important to back up as it contains the DB password as well as the 
encryption key needed to decode passwords stored in the DB.

However, this approach also results in a lot of wasted disk space and cost on S3 (or wherever you are keeping your backups).
Each set of `tar.gz` files is a standalone backup and hence contains all the data needed to restore your site.
Do this once a day and soon your S3 bill has 2 digits on it. Do this 4 times a day and you will be paying more for S3
than your servers. Sure, you could rotate the backups (manually, Frappe doesn't have built-in support) 
but we can do better - and spend fewer CPU cycles.

Now, with our servers seeing a lot more traffic and databases extending into the 10s of GB, I felt
we needed a slightly more custom solution. I have used Tarsnap in the past and that was my preferred 
solution but then came across this [podcast interview](https://changelog.com/gotime/48) with the creator of [Restic](https://restic.net/).
A quick search on the Frappe forum led me to [this post](https://discuss.frappe.io/t/how-to-backup-with-restic-to-s3-compatible-storage/87199) 
which covers much the same things as this blog post.


The main difference between the forum post and my setup is that we don't use `bench backup` at all.
Instead, we use `mysqldump` to create the DB snapshot (same as `bench backup`, without the `tar.gz`) and backup the site directory in its entirety - files and config.

> Specifically, the timestamped `tar.gz` files created by `bench backup` are [considered to be new files](https://restic.readthedocs.io/en/stable/040_backup.html#file-change-detection) by Restic and this would defeat the purpose of using Restic.

Our approach is simpler and has the advantage of being more suited to `restic` which can be smart about the changes in the files and do proper incremental backups.

_The Restic docs do a great job explaining how to get started - from initialising a `repo` to doing backups and restores. Read that to get a better understanding of Restic before using/adapting this script._

### Backup Script

#### `restic.sh`
```bash
#!/bin/bash
set -e
# Keep your exports in /etc/profile or similar
export AWS_ACCESS_KEY_ID=SOME_KEY
export AWS_SECRET_ACCESS_KEY=SOME_SECRET
export AWS_DEFAULT_REGION=ap-south-1
export RESTIC_PASSWORD_FILE=/path/to/restic.password
BUCKET=SOME_BUCKET
SITES=( site_1 site_2 site_3 )
DB_USER=SOME_DB_USER
DB_PASSWORD=SOME_DB_PASSWORD
for FRAPPE_SITE in "${SITES[@]}"
do
	echo "Backing Up $FRAPPE_SITE"
	DIR_PATH=frappe-bench/sites/$FRAPPE_SITE
	DB_NAME=`cat $DIR_PATH/site_config.json | jq -r '.db_name'`
	mysqldump --single-transaction --quick --lock-tables=false \
        -u $DB_USER -p$DB_PASSWORD $DB_NAME > $DIR_PATH/private/backups/$DB_NAME.sql
	RESTIC_URL="s3:s3.amazonaws.com/$BUCKET/restic/$FRAPPE_SITE"
	restic -r $RESTIC_URL list snapshots || restic -r $RESTIC_URL init
	restic -r $RESTIC_URL backup $PWD/frappe-bench/sites/$FRAPPE_SITE
	touch last_backup_$FRAPPE_SITE.timestamp
done
```

Here's a brief explainer:

- The `env` variables should go wherever you normally put your environment variables. DO NOT keep them in the script - that's an invitation for a breach at some later day.
- We are assuming there's a single DB user and password that can be used to access the DB for each
site. If not, you can also read the user and password from `site_config.json`
- You will need to install both `restic` and [`jq`](https://github.com/jqlang/jq) - e.g. `apt install restic jq`
- The `mysqldump` command is adapted from that used by `bench backup`. Be sure to use `--quick` - this helps keep [memory usage down](https://dev.mysql.com/doc/refman/5.7/en/mysqldump.html#option_mysqldump_quick) and can help prevent OOM crashes.
- We use the logical OR `||` to initialise the Restic repo if not already done. 
- Once the backup is completed, we use a simple timestamp to track when the last backup was completed.

I add this script to my Cron with `crontab -e` as an hourly task. This means I have more frequent backups and pay less than with the default `bench backup` approach. Admittedly, I can no longer use `bench restore` but on the other hand, all I have to do is `restic -r <repo> restore <snapshot> --target <target-dir>` and `mysql <db-name> < backup.sql`.


