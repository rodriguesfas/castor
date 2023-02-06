# Makefile version 22.03.05.1

# github actions env vars
ifeq ($(GITHUB_REF), refs/heads/main)
	ENVIRONMENT ?= production
endif
ifeq ($(GITHUB_REF), refs/heads/staging)
	ENVIRONMENT ?= staging
endif

# project settings
.DEFAULT_GOAL := all
PROJECT_NAME  ?= $(shell grep -rm1 'APPNAME' --include settings.py src/ | cut -f2 -d'"')
PROJECT_PATH  ?= src
ENVIRONMENT   ?= development
STACK_NAME    ?= "$(PROJECT_NAME)-$(ENVIRONMENT)-stack"
STACK_BUCKET  ?= "aws-sam-cli-$(ENVIRONMENT)-artifacts"

# venv settings
export PYTHONPATH := $(PROJECT_PATH):tests/fixtures
export VIRTUALENV := $(PWD)/.venv
export PATH       := $(VIRTUALENV)/bin:$(PATH)

# unittest logging level
test: export LOG_LEVEL=CRITICAL

# fix make < 3.81 (macOS and old Linux distros)
ifeq ($(filter undefine,$(value .FEATURES)),)
SHELL = env PATH="$(PATH)" /bin/bash
endif

.PHONY: .env .venv

all:

.venv:
	python3.8 -m venv $(VIRTUALENV)
	pip install --upgrade pip

clean::
	rm -rf .coverage .aws-sam .pytest_cache
	find $(PROJECT_PATH) -name __pycache__ | xargs rm -rf
	find tests -name __pycache__ | xargs rm -rf

install-hook:
	@echo "make lint" > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit

install-dev: .venv install-default install-hook
	pip install -r requirements-dev.txt

install-default:
	pip install -r requirements.txt

lint:
	black --line-length=100 --target-version=py38 --check .
	flake8 --max-line-length=100 --ignore=E402,W503,E712 --exclude .venv

format:
	black --line-length=100 --target-version=py38 .

test-integration:
	python -m unittest discover -p "itest*.py"

test:
	coverage run --source=$(PROJECT_PATH) -m unittest

pytest:
	python -m pytest
	
coverage: test .coverage
	coverage report -m --fail-under=90

migrate:
	aws lambda invoke --function-name $(PROJECT_NAME)-migrations result --log-type Tail > output
	@jq -r '.LogResult' output | base64 -d
	@HAS_ERROR=$$(jq 'has("FunctionError")' output) ; ! $$HAS_ERROR

package-default:
	pip install -r requiriments.txt -t .aws-sam/dependencies/python

deploy: package
	sam deploy \
		--stack-name $(STACK_NAME) \
		--s3-bucket $(STACK_BUCKET) \
		--capabilities CAPABILITY_IAM \
		--tags "stack=$(PROJECT_NAME)" \
		$(SAM_EXTRA_ARGS)

run-dev:
	python run.py

uninstall:
	virtualenv --clear .venv