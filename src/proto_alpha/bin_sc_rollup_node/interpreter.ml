(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 TriliTech <contact@trili.tech>                         *)
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

open Protocol
open Alpha_context
module Inbox = Store.Inbox

module type S = sig
  (** [update store event] interprets the messages associated with a chain [event].
      This requires the inbox to be updated beforehand. *)
  val update : Store.t -> Layer1.chain_event -> unit tzresult Lwt.t

  (** [start store] sets up the initial state for the PVM interpreter to work. *)
  val start : Store.t -> unit tzresult Lwt.t
end

module Make
    (PVM : Sc_rollup_PVM_sem.S
             with type context = Store.t
              and type state = Store.tree) : S = struct
  module PVM = PVM

  (** [eval_until_input state] advances a PVM [state] until it wants more inputs. *)
  let eval_until_input state =
    let open Lwt_syntax in
    let rec go ticks state =
      let* input_request = PVM.is_input_state state in
      match input_request with
      | Some input_request -> return (state, input_request, ticks)
      | None ->
          let* next_state = PVM.eval state in
          go (Int32.succ ticks) next_state
    in
    go Int32.zero state

  (** [transition_pvm store predecessor_hash hash] runs a PVM at the previous state
      [predecessor_hash] by consuming as many messages as possible from inbox at [hash]. *)
  let transition_pvm store predecessor_hash hash =
    let open Lwt_tzresult_syntax in
    let*! predecessor_state = Store.PVMState.find store predecessor_hash in
    let* predecessor_state =
      match predecessor_state with
      | None ->
          failwith
            "Missing PVM state for %s"
            (Block_hash.to_b58check predecessor_hash)
      | Some predecessor_state -> return predecessor_state
    in

    let*! inbox = Store.Inboxes.get store hash in
    let*! messages = Store.MessageTrees.get store hash in
    let inbox_level = Inbox.inbox_level inbox in

    let rec feed state num_messages num_ticks =
      (* TODO: [eval_until_input] returns the last input level and counter.
         We need to figure out the next! *)
      let*! (state, (want_inbox_level, message_counter), more_ticks) =
        eval_until_input state
      in
      let num_ticks = Int32.add num_ticks more_ticks in
      if Raw_level.(want_inbox_level > inbox_level) then
        (* We aren't at that inbox level yet. *)
        return (state, num_messages, num_ticks)
      else
        let*! payload = Inbox.get_message_payload messages message_counter in
        match payload with
        | Some payload ->
            let input =
              Sc_rollup_PVM_sem.{inbox_level; message_counter; payload}
            in
            let*! state = PVM.set_input input state in
            feed state (Int32.succ num_messages) num_ticks
        | None ->
            (* The message we want is not (yet?) available. *)
            return (state, num_messages, num_ticks)
    in

    let* (state, num_messages, num_ticks) =
      feed predecessor_state Int32.zero Int32.zero
    in
    let*! () =
      (* TODO: Use PVM's [get_tick] mechanism to find out the number of ticks! *)
      Store.PVMState.set store hash state
    in
    let*! () = Store.StateInfo.add store hash {num_messages; num_ticks} in
    return_unit

  (** [process_head store head] runs the PVM for the given head. *)
  let process_head store (Layer1.Head {hash; _} as head) =
    let open Lwt_tzresult_syntax in
    let*! predecessor_hash = Layer1.predecessor store head in
    transition_pvm store predecessor_hash hash

  let update store chain_event =
    let open Lwt_tzresult_syntax in
    match chain_event with
    | Layer1.SameBranch {intermediate_heads; new_head} ->
        let* () = List.iter_es (process_head store) intermediate_heads in
        process_head store new_head
    | Layer1.Rollback _new_head -> return_unit

  let start store =
    let open Lwt_tzresult_syntax in
    let*! gensis_state_exists =
      Store.PVMState.exists store Layer1.genesis_hash
    in
    unless gensis_state_exists (fun () ->
        let*! state = PVM.initial_state store "" in
        let*! () = Store.PVMState.set store Layer1.genesis_hash state in
        let*! () =
          Store.StateInfo.add
            store
            Layer1.genesis_hash
            {num_ticks = Int32.zero; num_messages = Int32.zero}
        in
        return_unit)
end

module Arith = Make (Pvm.Arith)
