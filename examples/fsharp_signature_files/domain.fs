namespace Domain

type OrderID =
  | OrderID of string

[<RequireQualifiedAccess>]
module OrderID =

  open System
  open System.Text.RegularExpressions

  let pattern = Regex "^[a-z][a-z0-9]{5}$"

  let tryParse (x : string) : OrderID option =
    if pattern.IsMatch(x) then
      Some (OrderID x)
    else
      None

  let toString (x : OrderID) : string =
    let (OrderID s) = x
    s
