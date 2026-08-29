module Warnings

type DasUnion =
| Case1 of string
| Case2 of int

let matchOnDasUnion union =
    match union with
    | Case1 s -> s
