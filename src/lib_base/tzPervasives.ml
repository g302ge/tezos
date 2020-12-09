(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

include Tezos_stdlib
module Error_monad = Tezos_error_monad.Error_monad
include Tezos_rpc
include Tezos_clic
include Tezos_crypto
include Tezos_micheline
module Data_encoding = Data_encoding
module Seq = Tezos_lwt_result_stdlib.Lwtreslib.Seq
module Map = Tezos_lwt_result_stdlib.Lwtreslib.Map
module Set = Tezos_lwt_result_stdlib.Lwtreslib.Set
module Hashtbl = Tezos_lwt_result_stdlib.Lwtreslib.Hashtbl
module Option = Tezos_lwt_result_stdlib.Lwtreslib.Option

module List = struct
  include Tezos_stdlib.TzList
  include Tezos_lwt_result_stdlib.Lwtreslib.List
end

module Result = Tezos_lwt_result_stdlib.Lwtreslib.Result
module WithExceptions = Tezos_lwt_result_stdlib.Lwtreslib.WithExceptions

module String = struct
  include String
  include Tezos_stdlib.TzString

  module Hashtbl = Tezos_lwt_result_stdlib.Lwtreslib.Hashtbl.MakeSeeded (struct
    type t = string

    let equal = String.equal

    let hash = Hashtbl.seeded_hash
  end)
end

module Time = Time
module Fitness = Fitness
module User_activated = User_activated
module Block_header = Block_header
module Genesis = Genesis
module Operation = Operation
module Protocol = Protocol
module Test_chain_status = Test_chain_status
module Preapply_result = Preapply_result
module Block_locator = Block_locator
module Mempool = Mempool
module P2p_addr = P2p_addr
module P2p_identity = P2p_identity
module P2p_peer = P2p_peer
module P2p_point = P2p_point
module P2p_connection = P2p_connection
module P2p_stat = P2p_stat
module P2p_version = P2p_version
module P2p_rejection = P2p_rejection
module Distributed_db_version = Distributed_db_version
module Network_version = Network_version
include Utils.Infix
include Error_monad
module Internal_event = Internal_event

module Filename = struct
  include Stdlib.Filename
  include Tezos_stdlib.TzFilename
end
