namespace Lib
    module Stuff =
        let rec fibonacci =
          Seq.unfold
            (fun (n0, n1) ->
                Some(n0, (n1, n0 + n1)))
            (0,1)

        let internal nonPublicMethod () = 42

