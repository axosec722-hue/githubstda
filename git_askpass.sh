#!/bin/bash

# Script to provide git credentials via GIT_ASKPASS

# This helper script is called by git when it needs a password
# It receives the prompt as first argument

echo "$GIT_PUSH_PASSWORD"
