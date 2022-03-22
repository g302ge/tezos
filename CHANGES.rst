Development Changelog
'''''''''''''''''''''

**NB:** The changelog for releases can be found at: https://tezos.gitlab.io/CHANGES.html


This file lists the changes added to each version of tezos-node,
tezos-client, and the other Octez executables. The changes to the economic
protocol are documented in the ``docs/protocols/`` directory; in
particular in ``docs/protocols/alpha.rst``.

When you make a commit on master, you can add an item in one of the
following subsections (node, client, …) to document your commit or the
set of related commits. This will ensure that this change is not
forgotten in the final changelog, which can be found in ``docs/CHANGES.rst``.
By having your commits update this file you also make it easy to find the
commits which are related to your changes using ``git log -p -- CHANGES.rst``.
Relevant items are moved to ``docs/CHANGES.rst`` after each release.

Only describe changes which affect users (bug fixes and new features),
or which will affect users in the future (deprecated features),
not refactorings or tests. Changes to the documentation do not need to
be documented here either.

Node
----

- **Breaking change**:
  restored the encoding of events corresponding to "completed
  requests" (block validation, head switch, ...) to pre v11. They only
  contains absolute timestamp.

- Add optional query parameters ``applied``, ``refused``, ``outdated``,
  ``branch_refused``, and ``branch_delayed`` to RPC
  ``GET /chains/main/mempool/pending_operations``.
  These new parameters indicate the classifications for which the RPC should
  or shouldn't return the corresponding operations. If no option is given, all
  the parameters are assumed to be ``true``, making this extension
  backward-compatible (i.e. and all operations are returned).

- Added optional parameter ``--media-type`` and its corresponding field
  in the configuration file. It defines which format of data serialisation
  must be used for RPC requests to the node. The value can be  ``json``,
  ``binary`` or ``any``. By default, the value is set to ``any``.

- Added an option ``--listen-prometheus <PORT>`` to ``tezos-node run`` to
  expose some metrics using the Prometheus format.

- Adds ``tezos-node storage head-commmit`` command to print the current
  context head commit hash to stdout.

- The node context storage format was upgraded. To this end, a new storage
  version was introduced: 0.0.7 (previously 0.0.6). Upgrading from 0.0.6 to
  0.0.7 is done automatically by the node the first time you run it. This
  upgrade is instantaneous. However, be careful that previous versions of Octez
  will refuse to run on a data directory which was used with Octez 12.0.

- Added a check to ensure the consistency between the imported
  snapshot history mode and the one stored in the targeted data
  directory configuration file.

Client
------

- A new ``--force`` option was added to the ``transfer`` command. It
  makes the client inject the transaction in a node even if the
  simulation of the transaction fails.

- A new ``--self-address`` option was added to the ``run script``
  command. It makes the given address be considered the address of
  the contract being run. The address must actually exist in the
  context. If ``--balance`` wasn't specified, the script also
  inherits the given contract's balance.

Baker / Endorser / Accuser
--------------------------

- The ``--liquidity-baking-escape-vote`` command-line has been renamed
  to ``--liquidity-baking-toggle-vote``.

- The ``--liquidity-baking-toggle-vote`` command-line option is made
  mandatory. The ``--votefile`` option can still be used to change
  vote without restarting the baker daemon, if both options are
  provided ``--votefile`` takes precedence and
  ``--liquidity-baking-toggle-vote`` is only used to define the
  default behavior of the daemon when an error occurs while reading
  the vote file.

- The format of the vote file provided by the ``--votefile`` option
  has changed too; the ``liquidity_baking_escape_vote`` key is renamed
  to ``liquidity_baking_toggle_vote`` and the value must now be one of
  the following strings: ``"on"`` to vote to continue Liquidity
  Baking, ``"off"`` to vote to stop it, or ``"pass"`` to abstain.

Signer
------

- Added global option ``--password-filename`` which acts as the client
  one. Option ``--password-file`` which actually was a complete no-op
  has been removed.

Proxy server
------------

- A new ``--data-dir`` option was added. It expects the path of the data-dir
  of the node from which to obtain data. This option greatly reduces the number of RPCs that
  the proxy server does to the node, hereby reducing IO consumption of the node.

Protocol Compiler And Environment
---------------------------------

Codec
-----

Docker Images
-------------

Miscellaneous
-------------
