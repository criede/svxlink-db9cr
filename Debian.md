steps to clone the orginal repo to build debian packets

# Locally: add the original as a second remote
git remote add upstream https://github.com/sm0svx/svxlink.git

# Fetch tags from the original and push them to the fork (one-time)
git fetch upstream --tags
git push origin --tags

# create .github/workflows/sync.yml
