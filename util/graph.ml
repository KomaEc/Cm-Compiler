
open Core

module type Graph_sig = sig 

  type vertex_t [@@deriving sexp]
  type t [@@deriving sexp]   
  type extern_t

  type load_error = [ `Duplicate_vertex of vertex_t ] [@@deriving sexp]
  exception Load_error of load_error [@@deriving sexp]

  val of_adjacency : extern_t -> [ `Ok of t | `Load_error of load_error ]
  val to_adjacency : t -> extern_t


  module Dijkstra : sig 
    type state 

    type error = [
      | `Relax of vertex_t
    ] [@@deriving sexp]
    exception Error of error [@@deriving sexp]

    val dijkstra : vertex_t -> t -> [ `Ok of state | `Error of error ]
    val d : state -> (vertex_t * float) list 
    val shortest_paths : state -> (vertex_t * vertex_t list) list
  end

end

module type GRAPH = sig 
  module type VERT = sig 
    type t [@@deriving sexp]
    include Comparable.S with type t := t
  end
  
  module type S = sig
    include Graph_sig
  end
  
  module Make : functor (V : VERT) -> 
    S with type vertex_t = V.t 
       and type extern_t = (V.t * (V.t * float) list) list
end  


module Graph : GRAPH = struct 
  module type VERT = sig 
    type t [@@deriving sexp]
    include Comparable.S with type t := t
  end
  
  module type S = sig
    include Graph_sig
  end

  module Make : functor (V : VERT) -> 
  S with type vertex_t = V.t 
     and type extern_t = (V.t * (V.t * float) list) list
  =
  functor (V : VERT) -> struct 
    module Map = V.Map 
    module Set = V.Set 

    type vertex_t = V.t [@@deriving sexp]
    type t = (vertex_t * float) list Map.t [@@deriving sexp] 
    type extern_t = (vertex_t * (vertex_t * float) list) list
    type load_error = [ `Duplicate_vertex of vertex_t ] [@@deriving sexp]
    exception Load_error of load_error [@@deriving sexp]

    let to_adjacency g = Map.to_alist g

    let of_adjacency_exn l =  match Map.of_alist l with
      | `Ok t -> t
      | `Duplicate_key c -> raise (Load_error (`Duplicate_vertex c))

    let of_adjacency l =
      try
        `Ok (of_adjacency_exn l)
      with
      | Load_error err -> `Load_error err


    module Dijkstra = struct

      type state = {
        src    :                  vertex_t
      ; g      :                         t
      ; d      :               float Map.t
      ; pred   :            vertex_t Map.t
      ; s      :                     Set.t
      ; v_s    : (vertex_t * float) Heap.t
      }

      let init src g =
        let init x = match V.equal src x with
          | true -> 0.0 | false -> Float.infinity in
        let d = List.fold (Map.keys g) ~init:Map.empty
            ~f:(fun acc x -> Map.set acc ~key:x ~data:(init x)) in
        {
          src
        ; g
        ; s = Set.empty
        ; d
        ; pred = Map.empty
        ; v_s = Heap.of_list (Map.to_alist d)
              ~cmp:(fun (_, e1) (_, e2) -> Float.compare e1 e2)
        }

      type error = [
        | `Relax of vertex_t
      ] [@@deriving sexp]
      exception Error of error [@@deriving sexp]

      let relax state (u, v, w) =
        let {d; pred; v_s; _} = state in
        let dv = match Map.find d v with
          | Some dv -> dv
          | None -> raise (Error (`Relax v)) in
        let du = match Map.find d u with
          | Some du -> du
          | None -> raise (Error (`Relax u)) in
        if dv > du +. w then
          let dv = du +. w in
          (match Heap.find_elt v_s ~f:(fun (n, _) -> V.equal n v) with
          | Some tok -> ignore (Heap.update v_s tok (v, dv))
          | None -> raise (Error (`Relax v))
          );
          { state with
            d = Map.change d v
                ~f:(function
                    | Some _ -> Some dv
                    | None -> raise (Error (`Relax v))
                  )
          ; pred = Map.set (Map.remove pred v) ~key:v ~data:u
          }
        else state

      let dijkstra_exn src g =
          let rec loop ({s; v_s; _} as state) =
            match Heap.is_empty v_s with
            | true -> state
            | false ->
              let u = fst (Heap.pop_exn v_s) in
              loop (
                List.fold (Map.find_exn g u)
                  ~init:{ state with s = Set.add s u }
                  ~f:(fun state (v, w) -> relax state (u, v, w))
              )
          in loop (init src g)
  
      let dijkstra src g =
        try
        `Ok (dijkstra_exn src g)
        with
        | Error err -> `Error err


      let d state = Map.to_alist (state.d)
            
      let path state n =
        let rec loop acc x =
          (match V.equal x state.src with
           | true -> x :: acc
           | false -> loop (x :: acc) (Map.find_exn state.pred x)
          ) in
        loop [] n
    
      let shortest_paths state =
      List.map (Map.keys state.g) ~f:(fun n -> (n, path state n)) 

      end

        
    
  end


end