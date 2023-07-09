#!/bin/sh
zola build
git add .
git commit 
git push
tar -C public -cvz . > site.tar.gz
hut pages publish -d tej.sh site.tar.gz
