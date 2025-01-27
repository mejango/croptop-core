#!/bin/bash

# The first argument is the path to the package.json file
PACKAGE_JSON_PATH="package.json"

# Get the current branch name
current_branch=$(git symbolic-ref --short HEAD)

# Check if the current branch is 'main' or 'master'
if [ "$current_branch" == "main" ] || [ "$current_branch" == "master" ]; then
  echo "You are on the $current_branch branch."
else
  echo "You are on the $current_branch branch, which is not 'main' or 'master'."
  exit 1
fi

# Pull in the latest changes
git pull

# Extract the package name from package.json
PACKAGE_NAME=$(grep '"name":' "$PACKAGE_JSON_PATH" | awk -F': ' '{print $2}' | tr -d '", ')

# Extract the current version from package.json
LOCAL_VERSION=$(grep '"version":' "$PACKAGE_JSON_PATH" | awk -F': ' '{print $2}' | tr -d '", ')

# Get the latest version from npm
NPM_VERSION=$(npm view $PACKAGE_NAME version)

# Compare versions
if [ "$LOCAL_VERSION" = "$NPM_VERSION" ]; then
  echo "WARNING: Bump the NPM version"
  exit 1
fi

# Move to the new version branch
git checkout -b "ci/$LOCAL_VERSION"

echo "Updating sphinx"
npx sphinx install

# Path to the .env file
ENV_FILE=".env"

# Check if the .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE does not exist."
    exit 1
fi

# Function to ensure file ends with newline
ensure_newline() {
    sed -i -e '$a\' "$ENV_FILE"
}

# Function to add or update a key-value pair
update_env_var() {
    local key=$1
    local value=$2
    if grep -q "^${key}=" "$ENV_FILE"; then
        # If key exists, replace the line
        sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        echo "Updated ${key} in $ENV_FILE"
    else
        # If key doesn't exist, add it
        ensure_newline
        echo "${key}=${value}" >> "$ENV_FILE"
        echo "Added ${key} to $ENV_FILE"
    fi
}

# Update SPHINX_MANAGED_BASE_URL
update_env_var "SPHINX_MANAGED_BASE_URL" "https://sphinx-backend-staging.up.railway.app"

# Update SPHINX_API_KEY
update_env_var "SPHINX_API_KEY" "48c06b32-834c-412a-9aee-d6a4e85d5581"

echo "Updating npm packages..."
npx npm-check-updates -u
npm install

echo "Syncing sphinx.lock"
npx sphinx sync --org-id ea165b21-7cdc-4d7b-be59-ecdd4c26bee4

echo "Running testnet deployment through sphinx"
npm run deploy:testnets