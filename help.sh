#!/bin/bash
set -e

KUBECTL_HELP=$(kubectl help)
KTL_HELP="\
Basic Commands (ktl):
  shell          Connects to the shell of a random pod selected by label and namespace
  pg:psql        Run psql with a production database
  pg:proxy       Port-forward production database to connect on localhost
  pg:dump        Dump PostgreSQL database into a directory
  pg:resotre     Restore PostgreSQL database from dump
  erl:shell      Connect to a shell of running Erlang/OTP node (executes wihin the pod)
  iex:remsh      Remote shell into a running Erlang/OTP node (via port-foward and iex --remsh)
  iex:observer   Connect to a running Erlang/OTP node an locally run observer
  status         Show version information for deployed containers

"

echo "${KUBECTL_HELP/Basic Commands (Beginner):/${KTL_HELP}Basic Commands (Beginner):}"
