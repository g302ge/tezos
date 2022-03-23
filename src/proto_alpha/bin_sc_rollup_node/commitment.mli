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

(** [get_last_commitment_level store] returns the level at which the last commitment 
was published. *)
val get_last_commitment_level : Store.t -> Raw_level.t Lwt.t

val update_last_commitment : Store.t -> Sc_rollup.Commitment.t -> unit Lwt.t

(** [start store rollup] initializes the inbox to track the messages published for
    the given [rollup]. *)
val start :
  Protocol_client_context.full ->
  Alpha_context.Sc_rollup.t ->
  unit tzresult Lwt.t
