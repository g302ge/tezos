(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Marigold <contact@marigold.dev>                        *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
(* Copyright (c) 2021 Oxhead Alpha <info@oxheadalpha.com>                    *)
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

(** This module introduces various functions to manipulate the storage related
    to commitments for transaction rollups. *)

(** [add_commitment context tx_rollup contract commitment] adds a
    commitment to a rollup.

    FIXME/TORU: https://gitlab.com/tezos/tezos/-/issues/2468

    We should document better the invariants. *)
val add_commitment :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Signature.Public_key_hash.t ->
  Tx_rollup_commitments_repr.Commitment.t ->
  Raw_context.t tzresult Lwt.t

(** [remove_bond context tx_rollup contract] removes the bond for an
    implicit contract.  This will fail if either the bond does not exist,
    or the bond is currently in-use. *)
val remove_bond :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Signature.public_key_hash ->
  Raw_context.t tzresult Lwt.t

(** [retire_rollup_level context tx_rollup level] removes all data
   associated with a level. It decrements the bonded commitment count
   for any contracts whose commitments have been either accepted or
   obviated (that is, neither accepted nor rejected).  This is normally
   used in finalization(during a Commitment operation) and is only
   public for testing.

   Returns:
     Commitment_too_late if we have not yet reached
   a level where we are allowed to finalize the commitment for
   this level.
     No_commitment if there has not yet been a commitment made
   for this level.
     Retired if the commitment for this level has been successfully
   retired. *)
val retire_rollup_level :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Raw_level_repr.t ->
  Raw_level_repr.t ->
  (Raw_context.t * [> `Commitment_too_late | `No_commitment | `Retired])
  tzresult
  Lwt.t

(** [get_commitments context tx_rollup level] returns the list of
   non-rejected commitments for a rollup at a level, first-submitted
   first. *)
val get_commitments :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Raw_level_repr.t ->
  (Raw_context.t * Tx_rollup_commitments_repr.t) tzresult Lwt.t

(** [pending_bonded_commitments ctxt tx_rollup contract] returns the
   number of commitments that [contract] has made that are still
   pending (that is, still subject to rejection). *)
val pending_bonded_commitments :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Signature.public_key_hash ->
  (Raw_context.t * int) tzresult Lwt.t

(** [has_bond ctxt tx_rollup contract] returns true if we have
    already collected a bond for [contract] for commitments on
    [tx_rollup]. *)
val has_bond :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Signature.public_key_hash ->
  (Raw_context.t * bool) tzresult Lwt.t

(** [finalize_pending_commitments ctxt tx_rollup last_level_to_finalize]
    finalizes all pending commitments that are old enough.  For each
    unfinalized level up to and including last_level_to_finalize, the
    oldest non-rejected commitment is chosen.  Any other commitments are
    deleted, and their transitive successors are also deleted. Because
    these commitments have not been rejected, their bonds are not
    slashed, but we still must maintain the count of bonded commitments.

    In the event that some level does not yet have any nonrejected
    commitments, the level traversal stops.

    The state is adjusted as well, tracking which levels have been
    finalized, and which are left to be finalized. *)
val finalize_pending_commitments :
  Raw_context.t ->
  Tx_rollup_repr.t ->
  Raw_level_repr.t ->
  Raw_context.t tzresult Lwt.t
