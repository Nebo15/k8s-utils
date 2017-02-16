# k8s-utils
Kubernetes utils for debugging our development or production environments

## erl-observe.sh
This script provides easy way to debug remote Erlang (or Elixir) nodes that is running in a Kubernetes cluster.

Application on remote node should include `:runtime_tools` in it's applications dependencies, otherwise
you will receive `rpc:handle_call` error.

  **Example usage:**
  
  ```
  ./bin/erl-observe.sh -l app=matcher -n mp
  ```

## pg-connect.sh
Port forward 5433 port to remote PostgreSQL database's 5432 port. Allows to query and debug it's state.


  **Example usage:**
  
  ```
  ./bin/pg-connect.sh -n mp -l app=postgres
  ```
