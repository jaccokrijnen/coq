(***********************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team    *)
(* <O___,, *        INRIA-Rocquencourt  &  LRI-CNRS-Orsay              *)
(*   \VV/  *************************************************************)
(*    //   *      This file is distributed under the terms of the      *)
(*         *       GNU Lesser General Public License Version 2.1       *)
(***********************************************************************)

(** Unicode utilities *)

type status = Letter | IdentPart | Symbol | Unknown

(* The following table stores classes of Unicode characters that
   are used by the lexer. There are 3 different classes so 2 bits are
   allocated for each character. We only use 16 bits over the 31 bits
   to simplify the masking process. (This choice seems to be a good
   trade-off between speed and space after some benchmarks.) *)

(* A 256 KiB table, initially filled with zeros. *)
let table = Array.make (1 lsl 17) 0

(* Associate a 2-bit pattern to each status at position [i].
   Only the 3 lowest bits of [i] are taken into account to
   define the position of the pattern in the word.
   Notice that pattern "00" means "undefined". *)
let mask i = function
  | Letter    -> 1 lsl ((i land 7) lsl 1) (* 01 *)
  | IdentPart -> 2 lsl ((i land 7) lsl 1) (* 10 *)
  | Symbol    -> 3 lsl ((i land 7) lsl 1) (* 11 *)
  | Unknown   -> 0 lsl ((i land 7) lsl 1) (* 00 *)

(* Helper to reset 2 bits in a word. *)
let reset_mask i =
  lnot (3 lsl ((i land 7) lsl 1))

(* Initialize the lookup table from a list of segments, assigning
   a status to every character of each segment. The order of these
   assignments is relevant: it is possible to assign status [s] to
   a segment [(c1, c2)] and later assign [s'] to [c] even if [c] is
   between [c1] and [c2]. *)
let mk_lookup_table_from_unicode_tables_for status tables =
  List.iter
    (List.iter
       (fun (c1, c2) ->
          for i = c1 to c2 do
            table.(i lsr 3) <-
              (table.(i lsr 3) land (reset_mask i)) lor (mask i status)
          done))
    tables

(* Look up into the table and interpret the found pattern. *)
let lookup x =
  let v = (table.(x lsr 3) lsr ((x land 7) lsl 1)) land 3 in
    if      v = 1 then Letter
    else if v = 2 then IdentPart
    else if v = 3 then Symbol
    else Unknown

(* [classify] discriminates between 3 different kinds of
   symbols based on the standard unicode classification (extracted from
   Camomile). *)
let classify =
  let single c = [ (c, c) ] in
    (* General tables. *)
    mk_lookup_table_from_unicode_tables_for Symbol
      [
        Unicodetable.sm;           (* Symbol, maths.                    *)
        Unicodetable.sc;           (* Symbol, currency.                 *)
        Unicodetable.so;           (* Symbol, modifier.                 *)
        Unicodetable.pd;           (* Punctuation, dash.                *)
        Unicodetable.pc;           (* Punctuation, connector.           *)
        Unicodetable.pe;           (* Punctuation, open.                *)
        Unicodetable.ps;           (* Punctution, close.                *)
        Unicodetable.pi;           (* Punctuation, initial quote.       *)
        Unicodetable.pf;           (* Punctuation, final quote.         *)
        Unicodetable.po;           (* Punctuation, other.               *)
      ];
    mk_lookup_table_from_unicode_tables_for Letter
      [
        Unicodetable.lu;           (* Letter, uppercase.                *)
        Unicodetable.ll;           (* Letter, lowercase.                *)
        Unicodetable.lt;           (* Letter, titlecase.                *)
        Unicodetable.lo;           (* Letter, others.                   *)
      ];
    mk_lookup_table_from_unicode_tables_for IdentPart
      [
        Unicodetable.nd;           (* Number, decimal digits.           *)
        Unicodetable.nl;           (* Number, letter.                   *)
        Unicodetable.no;           (* Number, other.                    *)
      ];

    (* Workaround. Some characters seems to be missing in
       Camomile's category tables. We add them manually. *)
    mk_lookup_table_from_unicode_tables_for Letter
      [
        [(0x01D00, 0x01D7F)];      (* Phonetic Extensions.              *)
        [(0x01D80, 0x01DBF)];      (* Phonetic Extensions Suppl.        *)
        [(0x01DC0, 0x01DFF)];      (* Combining Diacritical Marks Suppl.*)
      ];

    (* Exceptions (from a previous version of this function).           *)
    mk_lookup_table_from_unicode_tables_for Symbol
      [
        [(0x000B2, 0x000B3)];      (* Superscript 2-3.                  *)
        single 0x000B9;            (* Superscript 1.                    *)
        single 0x02070;            (* Superscript 0.                    *)
        [(0x02074, 0x02079)];      (* Superscript 4-9.                  *)
        single 0x0002E;            (* Dot.                              *)
      ];
    mk_lookup_table_from_unicode_tables_for Letter
      [
        single 0x005F;             (* Underscore.                       *)
        single 0x00A0;             (* Non breaking space.               *)
      ];
    mk_lookup_table_from_unicode_tables_for IdentPart
      [
        single 0x0027;             (* Single quote.                     *)
      ];
    (* Lookup *)
    lookup

exception End_of_input

let utf8_of_unicode n =
  if n < 128 then
    String.make 1 (Char.chr n)
  else
    let (m,s) = if n < 2048 then (2,192) else if n < 65536 then (3,224) else (4,240) in
    String.init m (fun i ->
        let j = (n lsr ((m - 1 - i) * 6)) land 63 in
        Char.chr (j + if i = 0 then s else 128))

(* If [s] is some UTF-8 encoded string
   and [i] is a position of some UTF-8 character within [s]
   then [next_utf8 s i] returns [(j,n)] where:
   - [j] indicates the position of the next UTF-8 character
   - [n] represents the UTF-8 character at index [i] *)
let next_utf8 s i =
  let err () = invalid_arg "utf8" in
  let l = String.length s - i in
  if l = 0 then raise End_of_input
  else let a = Char.code s.[i] in if a <= 0x7F then
    1, a
  else if a land 0x40 = 0 || l = 1 then err ()
  else let b = Char.code s.[i+1] in if b land 0xC0 <> 0x80 then err ()
  else if a land 0x20 = 0 then
    2, (a land 0x1F) lsl 6 + (b land 0x3F)
  else if l = 2 then err ()
  else let c = Char.code s.[i+2] in if c land 0xC0 <> 0x80 then err ()
  else if a land 0x10 = 0 then
    3, (a land 0x0F) lsl 12 + (b land 0x3F) lsl 6 + (c land 0x3F)
  else if l = 3 then err ()
  else let d = Char.code s.[i+3] in if d land 0xC0 <> 0x80 then err ()
  else if a land 0x08 = 0 then
    4, (a land 0x07) lsl 18 + (b land 0x3F) lsl 12 +
       (c land 0x3F) lsl 6 + (d land 0x3F)
  else err ()

let is_utf8 s =
  let rec check i =
    let (off, _) = next_utf8 s i in
    check (i + off)
  in
  try check 0 with End_of_input -> true | Invalid_argument _ -> false

(* Escape string if it contains non-utf8 characters *)

let escaped_non_utf8 s =
  let mk_escape x = Printf.sprintf "%%%X" x in
  let buff = Buffer.create (String.length s * 3) in
  let rec process_trailing_aux i j =
    if i = j then i else
      match String.unsafe_get s i with
      | '\128'..'\191' -> process_trailing_aux (i+1) j
      | _ -> i in
  let process_trailing i n =
    let j = if i+n-1 >= String.length s then i+1 else process_trailing_aux (i+1) (i+n) in
    (if j = i+n then
      Buffer.add_string buff (String.sub s i n)
    else
      let v = Array.init (j-i) (fun k -> mk_escape (Char.code s.[i+k])) in
      Buffer.add_string buff (String.concat "" (Array.to_list v)));
    j in
  let rec process i =
    if i >= String.length s then Buffer.contents buff else
      let c = String.unsafe_get s i in
      match c with
      | '\000'..'\127' -> Buffer.add_char buff c; process (i+1)
      | '\128'..'\191' | '\248'..'\255' -> Buffer.add_string buff (mk_escape (Char.code c)); process (i+1)
      | '\192'..'\223' -> process (process_trailing i 2)
      | '\224'..'\239' -> process (process_trailing i 3)
      | '\240'..'\247' -> process (process_trailing i 4)
  in
  process 0

let escaped_if_non_utf8 s =
  if is_utf8 s then s else escaped_non_utf8 s

(* Check the well-formedness of an identifier *)

let initial_refutation j n s =
  match classify n with
  | Letter -> None
  | _ ->
      let c = String.sub s 0 j in
      Some (false,
            "Invalid character '"^c^"' at beginning of identifier \""^s^"\".")

let trailing_refutation i j n s =
  match classify n with
  | Letter | IdentPart -> None
  | _ ->
      let c = String.sub s i j in
      Some (false,
            "Invalid character '"^c^"' in identifier \""^s^"\".")

let ident_refutation s =
  if s = ".." then None else try
    let j, n = next_utf8 s 0 in
      match initial_refutation j n s with
        |None ->
           begin try
             let rec aux i =
               let j, n = next_utf8 s i in
                 match trailing_refutation i j n s with
                   |None -> aux (i + j)
                   |x -> x
             in aux j
           with End_of_input -> None
           end
        |x -> x
  with
  | End_of_input -> Some (true,"The empty string is not an identifier.")
  | Invalid_argument _ -> Some (true,escaped_non_utf8 s^": invalid utf8 sequence.")

let lowercase_unicode =
  let tree = Segmenttree.make Unicodetable.to_lower in
  fun unicode ->
    try
      match Segmenttree.lookup unicode tree with
        | `Abs c -> c
        | `Delta d -> unicode + d
    with Not_found -> unicode

let lowercase_first_char s =
  assert (s <> "");
  let j, n = next_utf8 s 0 in
  utf8_of_unicode (lowercase_unicode n)

(** For extraction, we need to encode unicode character into ascii ones *)

let is_basic_ascii s =
  let ok = ref true in
  String.iter (fun c -> if Char.code c >= 128 then ok := false) s;
  !ok

let ascii_of_ident s =
  let len = String.length s in
  let has_UU i =
    i+2 < len && s.[i]='_' && s.[i+1]='U' && s.[i+2]='U'
  in
  let i = ref 0 in
  while !i < len && Char.code s.[!i] < 128 && not (has_UU !i) do
    incr i
  done;
  if !i = len then s else
    let out = Buffer.create (2*len) in
    Buffer.add_substring out s 0 !i;
    while !i < len do
      let j, n = next_utf8 s !i in
      if n >= 128 then
        (Printf.bprintf out "_UU%04x_" n; i := !i + j)
      else if has_UU !i then
        (Buffer.add_string out "_UUU"; i := !i + 3)
      else
        (Buffer.add_char out s.[!i]; incr i)
    done;
    Buffer.contents out

(* Compute length of an UTF-8 encoded string
   Rem 1 : utf8_length <= String.length (equal if pure ascii)
   Rem 2 : if used for an iso8859_1 encoded string, the result is
   wrong in very rare cases. Such a wrong case corresponds to any
   sequence of a character in range 192..253 immediately followed by a
   character in range 128..191 (typical case in french is "déçu" which
   is counted 3 instead of 4); then no real harm to use always
   utf8_length even if using an iso8859_1 encoding *)

(** FIXME: duplicate code with Pp *)

let utf8_length s =
  let len = String.length s
  and cnt = ref 0
  and nc = ref 0
  and p = ref 0 in
  while !p < len do
    begin
      match s.[!p] with
      | '\000'..'\127' -> nc := 0 (* ascii char *)
      | '\128'..'\191' -> nc := 0 (* cannot start with a continuation byte *)
      | '\192'..'\223' -> nc := 1 (* expect 1 continuation byte *)
      | '\224'..'\239' -> nc := 2 (* expect 2 continuation bytes *)
      | '\240'..'\247' -> nc := 3 (* expect 3 continuation bytes *)
      | '\248'..'\255' -> nc := 0 (* invalid byte *)
    end ;
    incr p ;
    while !p < len && !nc > 0 do
      match s.[!p] with
      | '\128'..'\191' (* next continuation byte *) -> incr p ; decr nc
      | _ (* not a continuation byte *) -> nc := 0
    done ;
    incr cnt
  done ;
  !cnt

(* Variant of String.sub for UTF8 character positions *)
let utf8_sub s start_u len_u =
  let len_b = String.length s
  and end_u = start_u + len_u
  and cnt = ref 0
  and nc = ref 0
  and p = ref 0 in
  let start_b = ref len_b in
  while !p < len_b && !cnt < end_u do
    if !cnt <= start_u then start_b := !p ;
    begin
      match s.[!p] with
      | '\000'..'\127' -> nc := 0 (* ascii char *)
      | '\128'..'\191' -> nc := 0 (* cannot start with a continuation byte *)
      |	'\192'..'\223' -> nc := 1 (* expect 1 continuation byte *)
      |	'\224'..'\239' -> nc := 2 (* expect 2 continuation bytes *)
      |	'\240'..'\247' -> nc := 3 (* expect 3 continuation bytes *)
      |	'\248'..'\255' -> nc := 0 (* invalid byte *)
    end ;
    incr p ;
    while !p < len_b && !nc > 0 do
      match s.[!p] with
      |	'\128'..'\191' (* next continuation byte *) -> incr p ; decr nc
      |	_ (* not a continuation byte *) -> nc := 0
    done ;
    incr cnt
  done ;
  let end_b = !p in
  String.sub s !start_b (end_b - !start_b)
