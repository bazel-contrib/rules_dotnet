namespace Domain

type OrderID = internal | OrderID of string

[<RequireQualifiedAccess>]
module OrderID =
  val tryParse : string -> OrderID option
  val toString : OrderID -> string
