#!/bin/sh
git push
zola build
tar -C public -cvz . > site.tar.gz
hut pages publish -d tej.srht.site site.tar.gz
