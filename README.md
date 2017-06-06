# k8s-utils
Kubernetes utils for debugging our development or production environments

## ktl

This command is a alias to the `kubectl` utility with custom subcommands:
  - `ktl shell -n{namespace} -l{selector}` - connect to a POD in a shell (/bin/sh) mode.
  - `ktl connect -n{namespace} [-l{selector}]` - port-forward PostgreSQL port and connect to it via GUI tool. Default label: `app=postgresql`.
  - `ktl connect -q -n{namespace} [-l{selector}]` - connect to a POD and enter `psql` shell. Default label: `app=postgresql`.
  - `ktl observer -n{namespace} -l{selector}` - debug remote Erlang VM in runtime via observer utility.
  - `ktl status` - Print information about cluster services and their latest versions on Docker Hub.
  - `ktl backup -n{namespace} [-l{selector} -t{table_names}]` - Dump PostgreSQL database. Default label: `app=postgresql`. Specify table names to dump only certain tables.
  - `ktl restore -n{namespace} [-l{selector} -t{table_names}]` - Restore PostgreSQL database from dump. Default label: `app=postgresql`. Specify table names to restore only certain tables.

In `[]` listed optional arguments.

## Installation

On macOS:
`ln -s {path_to_this repo}/ktl.sh /usr/local/bin/ktl`

On other OSes use other place for your symlink.
