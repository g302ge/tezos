(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Trili Tech, <contact@trili.tech>                       *)
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

(** The rollup node maintains an inbox of incoming messages.

   The incoming messages for a rollup are published on the layer 1. To
   maintain the state of its inbox, a rollup node retrieve these
   messages each time the tezos blockchain is updated.

   The inbox state is persistent.

*)
open Protocol

open Alpha_context

module State = struct
  (* TODO: copied from Inbox, move to a shared state between modules? *)
  let unstarted_failure () =
    Format.eprintf "Sc rollup node inbox is not started.\n" ;
    Lwt_exit.exit_and_raise 1

  let (set_sc_rollup_address, _get_sc_rollup_address) =
    let sc_rollup_address = ref None in
    ( (fun x -> sc_rollup_address := Some x),
      fun () ->
        match !sc_rollup_address with
        | None -> unstarted_failure ()
        | Some a -> a )

  let (set_sc_rollup_initial_level, _get_sc_rollup_initial_level) =
    let sc_rollup_initial_level = ref None in
    ( (fun x -> sc_rollup_initial_level := Some x),
      fun () ->
        match !sc_rollup_initial_level with
        | None -> unstarted_failure ()
        | Some a -> a )
end

let get_last_commitment_level store = Store.Last_commitment_level.get store

let update_last_commitment store (commitment : Sc_rollup.Commitment.t) =
  let inbox_level = commitment.inbox_level in
  Store.Commitments.add store inbox_level commitment

let start (cctxt : Protocol_client_context.full) sc_rollup_address =
  let open Lwt_tzresult_syntax in
  State.set_sc_rollup_address sc_rollup_address ;
  let+ initial_level =
    Plugin.RPC.Sc_rollup.initial_level
      cctxt
      (cctxt#chain, cctxt#block)
      sc_rollup_address
  in
  State.set_sc_rollup_initial_level initial_level
