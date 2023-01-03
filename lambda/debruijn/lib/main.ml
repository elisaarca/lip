open Ast

let parse (s : string) : namedterm =
  let lexbuf = Lexing.from_string s in
  let ast = Parser.prog Lexer.read lexbuf in
  ast

let rec free_vars t =
  let (@!) l1 l2 = List.fold_right 
    (fun x acc -> if List.exists ((=) x) l1 then acc else x::acc) l2 l1

  in match t with
  | NamedVar x -> [x]
  | NamedAbs(x,t) -> List.filter ((<>) x) (free_vars t)
  | NamedApp(t1,t2) -> (free_vars t1) @! (free_vars t2)

exception UnboundVar

let bind f x k = fun s -> if x = s then k else f s

(* Nameless representation of a named term t using an arbitrary mapping c of its
   free variables to De Bruijn indexes. Yields the corresponding n-term, where 
   n is the number of free variables present in t, namely the size of dom(c) *)
let dbterm_of_namedterm c t =
  let rec depth_of_term = function
    | NamedVar _ -> 0
    | NamedAbs(_,t) -> 1 + depth_of_term t
    | NamedApp(t1,t2) -> max (depth_of_term t1) (depth_of_term t2)
  in

  let depth = depth_of_term t in

  (* Helper function that carries:
     An environment env to keep track of the absolute position of each binder 
     hhe distance d from the outer-most enclosing binder *)
  let rec helper env d = function

    | NamedVar x -> DBVar(try
      (* The k-th enclosing binder (from right to left) for the name x equates 
         to: How many enclosing binders have I met? - When was this name bound?
         The most recently bound names get the smaller values *)
        d - env x

      (* If the name is not bound by an abstraction then it must be free;
       get its value from the context and shift it outside the bound region *)
      with
        UnboundVar -> c x + depth
    )

    (* Each abstraction is one level of depth lower than its body. The bound
       name is mapped to the current depth (starting from 1) *)
    | NamedAbs(x,u) -> DBAbs(helper (bind env x (d+1)) (d+1) u)
    | NamedApp(u,v) -> DBApp(helper env d u, helper env d v) 
  
  in helper (fun _ -> raise UnboundVar) 0 t

(* Nameless representation of a named term t using a default context *)
let dbterm_of_namedterm_auto t =
  let fv = free_vars t in

  (* Functional zip of two lists of equal size.
     a' list -> b' list -> (a' -> b') *)
  let rec fzip xs ys = match xs,ys with
    | [],[] -> fun _ -> failwith "Undefined"
    | [],_::_ | _::_,[] -> failwith "Cannot zip: lists do no match in size!"
    | x::xs',y::ys' -> bind (fzip xs' ys') x y
  in

  (* Establish a naming context for the free variables of t by assigning an
     increasing index to each one of them, right to left, starting from 0 *)
  let context = fzip fv (List.rev (List.init (List.length fv) (fun x -> x)))

  in dbterm_of_namedterm context t 

(* shift d c t is the d-place shift of a term t above cutoff *)
let rec shift d c = function
  | DBVar k -> DBVar (if k < c then k else k+d)
  | DBAbs t -> DBAbs (shift d (c+1) t)
  | DBApp(t1,t2) -> DBApp(shift d c t1, shift d c t2)