namespace Lib

type NullableEntity =
    static member TryFind(key: string) : string | null =
        if key = "present" then "value" else null

    static member Length(value: string) : int = value.Length

    static member DefinesNullable =
#if NULLABLE
        true
#else
        false
#endif
