#!/bin/bash
set -e

KUBECTL_HELP=$(kubectl help)
KTL_HELP="\
Basic Commands (ktl):
  promote        Promote staging image versions to production by updating values files
  shell          Connects to the shell of a random pod selected by label and namespace
  pg:ps          View active queries with execution time
  pg:kill        Kill a query.
  pg:outliers    Show queries that have longest execution time in aggregate
  pg:diagnose    Shows diagnostics report
  pg:psql        Run psql with a cluster database
  pg:open        Open local app binded to postgres:// protocol with a cluster database
  pg:proxy       Port-forward cluster database to connect on localhost
  pg:dump        Dumps PostgreSQL database to local directory in binary format
  pg:resotre     Restore PostgreSQL database from dump
  pg:copy        Copy query result from a remote PostgreSQL database and to a local one
  erl:shell      Connect to a Erlang shell of running Erlang/OTP node (executes wihin the pod)
  iex:shell      Connect to a IEx shell of running Erlang/OTP node (executes wihin the pod)
  iex:remsh      Remote shell into a running Erlang/OTP node (via port-foward and iex --remsh), run with sudo
  iex:observer   Connect to a running Erlang/OTP node an locally run observer, run with sudo
  status         Show version information for deployed containers

"

echo "${KUBECTL_HELP/Basic Commands (Beginner):/${KTL_HELP}Basic Commands (Beginner):}"
