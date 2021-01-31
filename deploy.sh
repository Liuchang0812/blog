#!/bin/bash

set -e -x

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
# hugo -t hugo-nuo # if using a theme, replace with `hugo -t <YOURTHEME>`

USER=root
HOST=138.68.7.76
DIR=/usr/share/nginx/html
hugo -t hugo-nuo && rsync -avz --delete public/ ${USER}@${HOST}:${DIR}
exit


# Go To Public folder
cd public
# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site `date`"
if [ $# -eq 1 ]
  then msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin master

# Come Back up to the Project Root
cd ..
