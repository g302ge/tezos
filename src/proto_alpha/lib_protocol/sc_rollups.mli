(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** Here is the list of PVMs available in this protocol.

    This list must only be appended for backward compatibility.
*)
type kind = Example_arith

val encoding : kind Data_encoding.t

(** [of_kind kind] returns the [PVM] of the given [kind]. *)
val of_kind : kind -> Sc_rollup_repr.PVM.t

(** [kind_of pvm] returns the [PVM] of the given [kind]. *)
val kind_of : Sc_rollup_repr.PVM.t -> kind

(** [from ~name] is [Some (module I)] if an implemented PVM called
     [name]. This function returns [None] otherwise. *)
val from : name:string -> Sc_rollup_repr.PVM.t option

(** [all] returns all implemented PVM. *)

val all : kind list

(** [all_names] returns all implemented PVM names. *)
val all_names : string list

(** [kind_of_string name] returns the kind of the PVM of the specified [name]. *)
val kind_of_string : string -> kind option

(** [string_of_kind kind] returns a human-readable representation of [kind]. *)
val string_of_kind : kind -> string

(** [pp] is a pretty-printer for [kind]. *)
val pp : Format.formatter -> kind -> unit
