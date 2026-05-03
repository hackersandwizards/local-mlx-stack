#!/usr/bin/env bash
find "$(dirname "$0")/../config/models" -name '*.env' -exec basename {} .env \; | sort
