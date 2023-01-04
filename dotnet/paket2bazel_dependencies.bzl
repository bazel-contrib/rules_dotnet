"Generated by paket2bazel"

load("@rules_dotnet//dotnet:defs.bzl", "nuget_repo")

def paket2bazel_dependencies():
    "paket2bazel_dependencies"
    nuget_repo(
        name = "paket2bazel_dependencies",
        packages = [
            ("Argu", "6.1.1", "sha512-ed1N3RMohnxS54MYuMgPz3766hXItY3L12IrPazZ+F8CXPKkxyV+p8xVkWmE5NDnRhEvaWptRhBrXstK9DhS/w==", ["FSharp.Core", "System.Configuration.ConfigurationManager"], []),
            ("Chessie", "0.6.0", "sha512-VUcf1SFTXQDf1ULVQ/IddKISCuVICj9OC+wW1LFSIDqpHfihP2M2CvLetBxsCvcplu8ugI4mo9ZV5gmdefHxPg==", ["NETStandard.Library", "FSharp.Core"], []),
            ("FSharp.Control.AsyncSeq", "3.2.1", "sha512-oV4Xx1MMOqpnZAon10bhN/JSUjwuc/H4hXq2SM7IWimfghk5yK85alZiqVH4momfGBKpr/RsBVfgCrqbmkaxJg==", ["FSharp.Core", "Microsoft.Bcl.AsyncInterfaces"], []),
            ("FSharp.Core", "6.0.3", "sha512-aDyKHiVFMwXWJrfW90iAeKyvw/lN+x98DPfx4oXke9Qnl4dz1sOi8KT2iczGeunqyWXh7nm+XUJ18i/0P3pZYw==", [], []),
            ("FSharp.SystemTextJson", "0.16.6", "sha512-7SoZOjo4dY6Ez47RSL5pWVAGiy8SPCzpjD4oBoGEkMNsnrRcy1WhD8jB2XyRufrboyBxKbGp7ZKMAQlDIc1Crg==", ["FSharp.Core", "System.Text.Json"], []),
            ("FSharpx.Async", "1.14.1", "sha512-8Ye/hgNHsnHWFtanfED+tgJJzPq4QEt+LUQ87Ie2JOiqb6WUP+vtF3WRBO2NIDqGQpivh207nwmCoFdK+T6jwQ==", ["FSharp.Control.AsyncSeq", "FSharp.Core"], []),
            ("FSharpx.Collections", "2.1.3", "sha512-1KSJLhLpqOTPRKYkgi0YvPrvGybiYi642r53VrQb1U7LNd3VQNsh3z++v69ky8FEj4y+kP6NPbgZbFyJ8mumqA==", ["FSharp.Core"], []),
            ("FSharpx.Extras", "3.0.0", "sha512-7Wv7LF8hZfGG6KuXcQoGTnm6keDAtMwvI6S2lK90Z23Dvs44XGeRAGOsLRO3dg2k6atckdt6xd0SDqQ9FSa4vA==", ["FSharp.Core", "FSharpx.Async", "FSharpx.Collections", "System.Reflection.Emit.Lightweight"], []),
            ("Microsoft.Bcl.AsyncInterfaces", "6.0.0", "sha512-IhoFoMkQ96h7Yg2PODHtOStOuV0RK+4nTTXycAmtKiZEXenXzSNf5vtKA/JVCHS9o7493dlu2vnAhSqcI9ewmQ==", [], []),
            ("Microsoft.CSharp", "4.7.0", "sha512-LJaYhRX5VxTUuD9WUPGD3GpWTgs89SVfoOPvSEdt66tL3lQvny9sR/ZiC3px1qUV5EFebS44i2CBeiliHVaQ3w==", [], []),
            ("Microsoft.NETCore.App.Ref", "6.0.5", "sha512-quj/gyLoZLypJO7PwsZ8ib6ZSgFv1C9s5SJgwzl/gztynTJ/3oO/stA2gNMf0C33vTJ0J3SSF/kRPQ/ifY5xZg==", [], ["Microsoft.CSharp|4.4.0", "Microsoft.Win32.Primitives|4.3.0", "Microsoft.Win32.Registry|4.4.0", "runtime.debian.8-x64.runtime.native.System|4.3.0", "runtime.debian.8-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.debian.8-x64.runtime.native.System.Net.Http|4.3.0", "runtime.debian.8-x64.runtime.native.System.Net.Security|4.3.0", "runtime.debian.8-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.debian.8-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.fedora.23-x64.runtime.native.System|4.3.0", "runtime.fedora.23-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Net.Http|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Net.Security|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.fedora.24-x64.runtime.native.System|4.3.0", "runtime.fedora.24-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Net.Http|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Net.Security|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Net.Http|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Net.Security|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Net.Http|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Net.Security|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.osx.10.10-x64.runtime.native.System|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Net.Http|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Net.Security|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.Apple|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.rhel.7-x64.runtime.native.System|4.3.0", "runtime.rhel.7-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Net.Http|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Net.Security|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "System.AppContext|4.3.0", "System.Buffers|4.4.0", "System.Collections|4.3.0", "System.Collections.Concurrent|4.3.0", "System.Collections.Immutable|1.4.0", "System.Collections.NonGeneric|4.3.0", "System.Collections.Specialized|4.3.0", "System.ComponentModel|4.3.0", "System.ComponentModel.EventBasedAsync|4.3.0", "System.ComponentModel.Primitives|4.3.0", "System.ComponentModel.TypeConverter|4.3.0", "System.Console|4.3.0", "System.Data.Common|4.3.0", "System.Diagnostics.Contracts|4.3.0", "System.Diagnostics.Debug|4.3.0", "System.Diagnostics.DiagnosticSource|4.4.0", "System.Diagnostics.FileVersionInfo|4.3.0", "System.Diagnostics.Process|4.3.0", "System.Diagnostics.StackTrace|4.3.0", "System.Diagnostics.TextWriterTraceListener|4.3.0", "System.Diagnostics.Tools|4.3.0", "System.Diagnostics.TraceSource|4.3.0", "System.Diagnostics.Tracing|4.3.0", "System.Dynamic.Runtime|4.3.0", "System.Globalization|4.3.0", "System.Globalization.Calendars|4.3.0", "System.Globalization.Extensions|4.3.0", "System.IO|4.3.0", "System.IO.Compression|4.3.0", "System.IO.Compression.ZipFile|4.3.0", "System.IO.FileSystem|4.3.0", "System.IO.FileSystem.AccessControl|4.4.0", "System.IO.FileSystem.DriveInfo|4.3.0", "System.IO.FileSystem.Primitives|4.3.0", "System.IO.FileSystem.Watcher|4.3.0", "System.IO.IsolatedStorage|4.3.0", "System.IO.MemoryMappedFiles|4.3.0", "System.IO.Pipes|4.3.0", "System.IO.UnmanagedMemoryStream|4.3.0", "System.Linq|4.3.0", "System.Linq.Expressions|4.3.0", "System.Linq.Queryable|4.3.0", "System.Net.Http|4.3.0", "System.Net.NameResolution|4.3.0", "System.Net.Primitives|4.3.0", "System.Net.Requests|4.3.0", "System.Net.Security|4.3.0", "System.Net.Sockets|4.3.0", "System.Net.WebHeaderCollection|4.3.0", "System.ObjectModel|4.3.0", "System.Private.DataContractSerialization|4.3.0", "System.Reflection|4.3.0", "System.Reflection.Emit|4.3.0", "System.Reflection.Emit.ILGeneration|4.3.0", "System.Reflection.Emit.Lightweight|4.3.0", "System.Reflection.Extensions|4.3.0", "System.Reflection.Metadata|1.5.0", "System.Reflection.Primitives|4.3.0", "System.Reflection.TypeExtensions|4.3.0", "System.Resources.ResourceManager|4.3.0", "System.Runtime|4.3.0", "System.Runtime.Extensions|4.3.0", "System.Runtime.Handles|4.3.0", "System.Runtime.InteropServices|4.3.0", "System.Runtime.InteropServices.RuntimeInformation|4.3.0", "System.Runtime.Loader|4.3.0", "System.Runtime.Numerics|4.3.0", "System.Runtime.Serialization.Formatters|4.3.0", "System.Runtime.Serialization.Json|4.3.0", "System.Runtime.Serialization.Primitives|4.3.0", "System.Security.AccessControl|4.4.0", "System.Security.Claims|4.3.0", "System.Security.Cryptography.Algorithms|4.3.0", "System.Security.Cryptography.Cng|4.4.0", "System.Security.Cryptography.Csp|4.3.0", "System.Security.Cryptography.Encoding|4.3.0", "System.Security.Cryptography.OpenSsl|4.4.0", "System.Security.Cryptography.Primitives|4.3.0", "System.Security.Cryptography.X509Certificates|4.3.0", "System.Security.Cryptography.Xml|4.4.0", "System.Security.Principal|4.3.0", "System.Security.Principal.Windows|4.4.0", "System.Text.Encoding|4.3.0", "System.Text.Encoding.Extensions|4.3.0", "System.Text.RegularExpressions|4.3.0", "System.Threading|4.3.0", "System.Threading.Overlapped|4.3.0", "System.Threading.Tasks|4.3.0", "System.Threading.Tasks.Extensions|4.3.0", "System.Threading.Tasks.Parallel|4.3.0", "System.Threading.Thread|4.3.0", "System.Threading.ThreadPool|4.3.0", "System.Threading.Timer|4.3.0", "System.ValueTuple|4.3.0", "System.Xml.ReaderWriter|4.3.0", "System.Xml.XDocument|4.3.0", "System.Xml.XmlDocument|4.3.0", "System.Xml.XmlSerializer|4.3.0", "System.Xml.XPath|4.3.0", "System.Xml.XPath.XDocument|4.3.0"]),
            ("Microsoft.NETCore.Platforms", "6.0.5", "sha512-GTMT/dgCRBCRUj11ssZ8K1FJm6Md+C/tSJl8I7YjxOFwSvopaIneV32y1VlnBTI4wy1SwueI7ou2sVfHkWENrA==", [], []),
            ("Microsoft.NETCore.Targets", "5.0.0", "sha512-hYHm3JAjQO/nySxcl1EpZhYEW+2P3H1eLZNr+QxgO5TnLS6hqtfi5WchjQzjid45MYmhy2X7IOmcWtDP4fpMGw==", [], []),
            ("Microsoft.Web.Xdt", "3.1.0", "sha512-3VApgkdgOglJWtrXSgYzz6o8Cp6IpvmFQMeICyQvvbKoy+OjNwco5ovzBBL1HHj7kEgLfe2ruXW/ZQ1k+2YxYw==", [], []),
            ("Microsoft.Win32.SystemEvents", "6.0.1", "sha512-tCbvWn9ymrxUuAlYZCQ7eDwVSn7571UIeMYWizWCXPjQlESdfIGr1W6EXhrFm8BgPt2e9G5bJfxVrzx2knWR6A==", [], []),
            ("Mono.Cecil", "0.11.4", "sha512-CnjwUMmFHnScNG8e/4DRZQQX67H5ajekRDudmZ6Fy1jCLhyH1jjzbQCOEFhBLa2NjPWQpMF+RHdBJY8a7GgmlA==", [], []),
            ("NETStandard.Library", "2.0.3", "sha512-548M6mnBSJWxsIlkQHfbzoYxpiYFXZZSL00p4GHYv8PkiqFBnnT68mW5mGEsA/ch9fDO9GkPgkFQpWiXZN7mAQ==", ["Microsoft.NETCore.Platforms"], []),
            ("Newtonsoft.Json", "13.0.1", "sha512-g3MbZi6vBTeaI/hEbvR7vBETSd1DWLe9i1E4P+nPY34v5i94zqUqDXvdWC3G+7tYN9SnsdU9zzegrnRz4h7nsQ==", [], []),
            ("NuGet.Commands", "6.3.0", "sha512-Sku4aLa2P6fu/yU23cCaXtG33lBC5yZ4CskiCECnKMKhoiONQx/9ts66B7doJjwctb37w3FJAo9yE7gwzfUOZA==", ["NuGet.Credentials", "NuGet.ProjectModel"], []),
            ("NuGet.Common", "6.3.0", "sha512-qIXPWAhirtrK3QU/ZWBd0NYLdPfZL5XAWZepacZDUKuOJ8a+2hlcVP7ohvN6RzYk4LcBN3HgguFhoKdZLM4brA==", ["NuGet.Frameworks"], []),
            ("NuGet.Configuration", "6.3.0", "sha512-mFn4cXvExSjgUooFPEqq5Gtsp8a7ANdu5LjDzysdJkziDkWkUa6x07xjZCzINQZoe9Y/OtOuQRMaAE1UA8dyPw==", ["NuGet.Common", "System.Security.Cryptography.ProtectedData"], []),
            ("NuGet.Credentials", "6.3.0", "sha512-5xA2dW8YdEBLYtu+SkZ6QyxrZt6vxmPTW521nSq9BE8DgNS2BpwPwo1sFcYbM+devU9bSYCIPIg8CpSQHF2YVA==", ["NuGet.Protocol"], []),
            ("NuGet.DependencyResolver.Core", "6.3.0", "sha512-7sgzHc9ZPa39YlVBfyFqGyNEflQOH9AmDo2M3vzrGtkoDgMIlmTeRZm/3P6R4rjoo1DFNUcTRAepDesaXRf9tA==", ["NuGet.Configuration", "NuGet.LibraryModel", "NuGet.Protocol"], []),
            ("NuGet.Frameworks", "6.3.0", "sha512-1qR5DUYtyBi1Vfl70p3Rv+TVLp0InZkwSQuedRAklLzDbsDiCX9IDFOZaBuoFYEVp8z3+/tABujlzJwoSh28Hg==", [], []),
            ("NuGet.LibraryModel", "6.3.0", "sha512-OPXNh1kxH+a/KSQ3y7QZiZS9/hQSTvmATfzW58LHCGSnBt9uXFz175omQFTfzRT2zhmxD3G8llp1eh9lRAgIUQ==", ["NuGet.Common", "NuGet.Versioning"], []),
            ("NuGet.PackageManagement", "6.2.0", "sha512-pHKYJIu77c9RHdV1t8FvrzipVgQgBxDnGZB+/IsSfnH7h6ZGdkRg74MDTgh3uJbIoU4ggC3RLbaDGxsPz6qWIQ==", ["NuGet.Commands", "NuGet.Resolver", "Microsoft.CSharp", "Microsoft.Web.Xdt", "System.ComponentModel.Composition"], []),
            ("Nuget.Packaging", "6.3.0", "sha512-qTv1nY3kH0DOly5kNaVFPTW8kta63YMqw3Xp3JBK5nt+EZW/iZvN1NcQ+YEHuW+2ktn6I6lQ/9MNv8I9Tv4DtA==", ["NuGet.Configuration", "NuGet.Versioning", "Newtonsoft.Json", "System.Security.Cryptography.Cng", "System.Security.Cryptography.Pkcs"], []),
            ("NuGet.ProjectModel", "6.3.0", "sha512-8nHo2PxZ4uIW9V2u+h/A/rJJHBuWv+QCImIoKLwCKT8YKGBHKW+MpFlP5NV59JficVFITJtjeCFgWQjEUoPcFA==", ["NuGet.DependencyResolver.Core"], []),
            ("NuGet.Protocol", "6.3.0", "sha512-6nLnh/bPnf4KGwtWeait6J8wgON+hNUtfAU7f3cDKECHqUdzNsxz78iHu/ia2wgBx3Uq9xj0Ne/mNRIKII16GQ==", [], []),
            ("NuGet.Resolver", "6.3.0", "sha512-hdmaUD7+q7qfBY8NiK9OYBpmUlO6LhktKGDCpB7SerE3YYZC1jq09bUQfYjBya0MVGN6UvmpVnQRlc7MHX5WMg==", ["NuGet.Protocol"], []),
            ("NuGet.Versioning", "6.3.0", "sha512-66/JrnvBv9W/MW2M6OhHF8oJhhEPxQVPBYh/B7WsYn6z/qaM+FwGjiX3yiIJPoo/wSZ0bbkMsITbdcuemN4WBA==", [], []),
            ("Paket.Core", "7.1.5", "sha512-XT8Jdh8NOJU6CZDuGXaL4mirvwLscK5MarhCBJlT9RAtTq79qQuSc9dklEkfGMkyif/s36oMQtaQIZ914vzJHg==", ["Chessie", "FSharp.Core", "Mono.Cecil", "Newtonsoft.Json", "Nuget.Packaging", "System.Net.Http", "System.Net.Http.WinHttpHandler", "System.Security.Cryptography.ProtectedData"], []),
            ("runtime.debian.8-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-s9AMelYhmifrJqGjkRkqyoP7NMudky0vJPdYzjGKryWYhofREwzC4EesqYm+dooMQB++vbgvGrtrcZpU36Q+sA==", [], []),
            ("runtime.debian.9-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-1kcSfJKTg00KxR43jsnYjjYTPoUh+f+OLpL4/yF/bzKikgxV6QPlz74UyrypYprz3NUHHOcsa12E7+Xp4RtTng==", [], []),
            ("runtime.fedora.23-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-DPcJlXiNYg8lqqCAFTgaL9Yqs1brKG3H6b1XVimLf9RYxW7zOLujvf3HfTlvrYEWsAulgJ/+7Gh0mCw4FUt+IQ==", [], []),
            ("runtime.fedora.24-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-2p9EjZTy8LkH/wx6OwRuk0ORuVL7PzqJ3cdvL/SY58Ep+XW0AYEBjyy7kloJ/nPZGYVUT+NS8kNwPU5ICV/DwQ==", [], []),
            ("runtime.fedora.27-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-2v5kHzEZgBFCz+5NJgZn3Dmi9gaYY/loR5PJEXvOJ018XIF6BmSGYNyHNXTmdFPq50EjwaGpHj8cQmR3z5oeGA==", [], []),
            ("runtime.fedora.28-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-qfB0WU/HXLYhTlXpDZi0eY1p1x9jlwxDlVFcWrj9u+2gFEesUKux9IoR9bzQLPPj//B0dSWolKEgW/1X70VWCA==", [], []),
            ("runtime.native.System", "4.3.1", "sha512-AJsN0GLPijYtmFZdvPYnfTdAMTlvMttusjye6ZC1Edg5XUneNv1BCHzXfM0SWpqf+Gt/31WthibAPAorcN4F1g==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets"], []),
            ("runtime.native.System.Net.Http", "4.3.1", "sha512-n3clBjCv4nEoDl/hV4/DYwi/yoRrFZk9Tpe0TenLiITLHvtijO+OSYhwV7JmACcsZlLFKMaYW+P5yN3sK/xU0Q==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets"], []),
            ("runtime.native.System.Security.Cryptography.Apple", "4.3.1", "sha512-C+AZUmQBFgXR/NxF80q0Sy7SgYiW+C3CcIuA7yd0f1FXWN16xhIRSmXN92IUSGx/ebGN3XmaeuVUZpd+NuY/jQ==", ["runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.Apple"], []),
            ("runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-CiS94rEK+DWQJJbFqOc+SboSZQeswgRiao5QMZjHjhhRPi2NkawZZ0l99i8+eGNTVo6f4cYTOXVmNr0BeJTiYQ==", ["runtime.debian.8-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.debian.9-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.fedora.23-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.fedora.24-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.fedora.27-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.fedora.28-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.opensuse.42.3-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.rhel.7-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography.OpenSsl", "runtime.ubuntu.18.04-x64.runtime.native.System.Security.Cryptography.OpenSsl"], []),
            ("runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-kbvMwf5iS0oM7qiHPy3sHADQa2ncqFXVz7bQKCiPKcnNu5NTDz4cO/Nk4gy54iYjU0SSma/z2IfYIpPGVsdiZA==", [], []),
            ("runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-anMSS/nfTUvTuvUE3jg+sSEx7JUgLkeYS7T9dbb8ZE42XYWdaLJjRlp3qA/yYyoewJuVJ6ZPeI8w9QrlKgVSow==", [], []),
            ("runtime.opensuse.42.3-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-KHQzsD6iTnD3Rpr+Odhe0II9LMwTJkIOMKekGzBz5TQlNbEpuc0LwQxMuCE4FZnzcefRYw3kDd5Xyu+AFND8FQ==", [], []),
            ("runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.Apple", "4.3.1", "sha512-YVeP6XccbJen1k3sjfntjqWS+vAcVt37VW3eBuZvjH7ZlTmQz3t6n8gLNh342IeDSBM+06SPYtBqP1roAlIpDA==", [], []),
            ("runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-KBHT4RWCC3klyYzHWLweXSAPRzPLuzFdfixnzojA+tNUE6kHpyABhtbgTiwhGHyA3+TlyLOn1viw1NBoG7ZOxQ==", [], []),
            ("runtime.rhel.7-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-Lmw34chaD1jDOrmiEl2jIXVoCfYhTFMWQWtC47RDRLKYpwLOjOkSa6E2LM5K28UNpkSOZu579Os/t+eZ+wAhOw==", [], []),
            ("runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-K6KLKN1ICpOqvVG2Dub+uX3gb/MqqiS1deVZpuj46M7ya9ranrGzFYVIMsQFI8f7vhc+sf0gyTtN0es9tN4jmw==", [], []),
            ("runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-IXiZH+OL4lP8dRKieebADFgWPgyq/vbMbYqXCz9EhfaU4CcRl1ygb3pmpNWhVJsVEV3fRb3tEaEFowmkb56WCQ==", [], []),
            ("runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-uOpq6ML3XC+QioF01mDpg6zuJEZs23+vjpbnOKQkZxyMSOGNanyleAjNgXLZyUo0NPa5c8QIMB878SvxLSxjhA==", [], []),
            ("runtime.ubuntu.18.04-x64.runtime.native.System.Security.Cryptography.OpenSsl", "4.3.3", "sha512-fefg8Dxuv7BKypFbd1HKIdO/x51l+NN4WP5GIqe+Gx6El1Aut7zZA5a9B8WPowDiGCwPIqEJaIhdwCjmbHqscQ==", [], []),
            ("System.Collections", "4.3.0", "sha512-ynuVLTDaFIfKTkOqUigXte4m5+EFNwYoEBEvxnp1EnZsOdQC85S7BCbREIu8+bu2Tpzh9a9zbvIVpRo15V8FGw==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Collections.Concurrent", "4.3.0", "sha512-NcGqPmNiFv5dwuvrUEKT5prWNV0m4iRTrwYK+U2CefqpO9z+EnrssLMWx+fZGFvKxy6ZSYTv238thRXx9Vz2gg==", ["System.Collections", "System.Diagnostics.Debug", "System.Diagnostics.Tracing", "System.Globalization", "System.Reflection", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Threading", "System.Threading.Tasks"], []),
            ("System.ComponentModel.Composition", "6.0.0", "sha512-YWQ3ENu0D2st9ZV+Yj4u3IFcas0Pw7S4c7ymDUooPLb1psNJ53YniX2orSiY2OlRWnssaUsTytnVJa/KfCn5aA==", [], []),
            ("System.Configuration.ConfigurationManager", "6.0.0", "sha512-3ljLko1jA6FjAf16qO2sN53+bEfm2AshZl+SurndX/UrPiRM9t8PlF8ccucckjN1YdvydS/DMkF0qMnsxwwyRw==", ["System.Security.Cryptography.ProtectedData", "System.Security.Permissions"], []),
            ("System.Diagnostics.Debug", "4.3.0", "sha512-bFj+HjYY5/h2hMHOp+/H07Gb19+NJTX54ntixS9EHxG2eyEiXWvNYvQJ4CwqFiMcTbGb4zuPq1ubClyGYN2rJA==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Diagnostics.DiagnosticSource", "6.0.0", "sha512-dYnmo66bitfHxLjNBU2LPp6Dn98n7hRyk7ZKGVzaAPw2MHy+40dLxfw7susxMkWfL3C//aJF+/UDAPgH2YhUZg==", ["System.Runtime.CompilerServices.Unsafe"], []),
            ("System.Diagnostics.Tracing", "4.3.0", "sha512-0KXTDiYc1Ft9+rArf/vXa2TgybiS7YJuphSByYPAIIsFtpmBzXnpHNTlgR4c1MPOoGoa/OBYEezli+XkwgFp6g==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Drawing.Common", "6.0.0", "sha512-1h8KPgHD6sFfE/wboEosfOTqyVZACy+qNh/sq9ODbUnVvTRPOYXuPZTNw/anK44H5CPNspZbT1yiIitd4ymI5A==", ["Microsoft.Win32.SystemEvents"], []),
            ("System.Formats.Asn1", "6.0.0", "sha512-62YP6zLnvmFtFI3rjybbrnSeK6hHQCaFfJJfoNhQqrETJBPehSucQxIyQs5W+GGBW/rpSXD/0NqNW7mttIWXhA==", [], []),
            ("System.Globalization", "4.3.0", "sha512-gj0rowjLBztAoxRuzM0Nn9exYVrD+++xb3PYc+QR/YHDvch98gbT3H4vFMnNU6r8poSjVwwlRxKAqtqN6AXs4g==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Globalization.Calendars", "4.3.0", "sha512-6XGQIxQCs5N3S5Je/AKiv6QdHRF6F/uH2m45n1I0VGlidn6c2POZcO+kCOT0U80eZ1Giph42a8l0BuGwuKS+hg==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Globalization", "System.Runtime"], []),
            ("System.Globalization.Extensions", "4.3.0", "sha512-pNNgAD+V4MMe3znAuR4cc4UKYKxdADKxfbiIo8fXE0zvms2XIZ0UF0rSE7fARPSbNkzFcgBz6/y24b9uTsJM5Q==", ["Microsoft.NETCore.Platforms", "System.Globalization", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.InteropServices"], []),
            ("System.IO", "4.3.0", "sha512-v8paIePhmGuXZbE9xvvNb4uJ5ME4OFXR1+8la/G/L1GIl2nbU2WFnddgb79kVK3U2us7q1aZT/uY/R0D/ovB5g==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime", "System.Text.Encoding", "System.Threading.Tasks"], []),
            ("System.IO.FileSystem", "4.3.0", "sha512-T7WB1vhblSmgkaDpdGM3Uqo55Qsr5sip5eyowrwiXOoHBkzOx3ePd9+Zh97r9NzOwFCxqX7awO6RBxQuao7n7g==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.IO", "System.IO.FileSystem.Primitives", "System.Runtime", "System.Runtime.Handles", "System.Text.Encoding", "System.Threading.Tasks"], []),
            ("System.IO.FileSystem.Primitives", "4.3.0", "sha512-WIWVPQlYLP/Zc9I6IakpBk1y8ryVGK83MtZx//zGKKi2hvHQWKAB7moRQCOz5Is/wNDksiYpocf3FeA3le6e5Q==", ["System.Runtime"], []),
            ("System.Linq", "4.3.0", "sha512-6sx/4exSb0BfW6DmcfYW0OW+nBgo1UOp4vjGXfQJnWsupKn6LNrk80sXDcNxQvYOJn4TfKOfNQKB7XDS3GIEWA==", ["System.Collections", "System.Diagnostics.Debug", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions"], []),
            ("System.Net.Http", "4.3.4", "sha512-Fj7e73NNHwof97gFPTJuq8gv6G895yxkZt14DVnZdEh4gvKl8WrksCwNjIp/JeYX/yu/qxM/iOv9ai+ZY3Fp7Q==", ["Microsoft.NETCore.Platforms", "runtime.native.System", "runtime.native.System.Net.Http", "runtime.native.System.Security.Cryptography.OpenSsl", "System.Collections", "System.Diagnostics.Debug", "System.Diagnostics.DiagnosticSource", "System.Diagnostics.Tracing", "System.Globalization", "System.Globalization.Extensions", "System.IO", "System.IO.FileSystem", "System.Net.Primitives", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.Handles", "System.Runtime.InteropServices", "System.Security.Cryptography.Algorithms", "System.Security.Cryptography.Encoding", "System.Security.Cryptography.OpenSsl", "System.Security.Cryptography.Primitives", "System.Security.Cryptography.X509Certificates", "System.Text.Encoding", "System.Threading", "System.Threading.Tasks"], []),
            ("System.Net.Http.WinHttpHandler", "6.0.1", "sha512-uLH7CWm9PZaO0SNhnEL8wvLCwcLCjC9M/jWgl7kTwp5PuFCfeCn7hrq6c0Bpfq2s1SCkx9lNUoRWnM76wMpnxQ==", [], []),
            ("System.Net.Primitives", "4.3.1", "sha512-BgdlyYCI7rrdh36p3lMTqbkvaafPETpB1bk9iQlFdQxYE692kiXvmseXs8ghL+gEgQF2xgDc8GH4QLkSgUUs+Q==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime", "System.Runtime.Handles"], []),
            ("System.Reflection", "4.3.0", "sha512-IyW2ftYNzgMCgHBk8lQiy+G3+ydbU5tE+6PEqM5JJvIdeFKaXDSzHAPYDREPe6zpr5WJ1Fcma+rAFCIAV6+DMw==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.IO", "System.Reflection.Primitives", "System.Runtime"], []),
            ("System.Reflection.Emit.Lightweight", "4.7.0", "sha512-Blr1A9Vqk+ZUknlk6sFrhOcpuqx4bp7kqwZfhwkmmhz+9dgOl8cZ9CnSXbalbL9rfHmi5HDFydxQsfozl2PvjQ==", [], []),
            ("System.Reflection.Primitives", "4.3.0", "sha512-1LnMkF9aXKuQAgYzjoiQaL9mwY7oY6KdaO/zzeLMynNBEqKoUfLi5TiKIewoAF+hkxfGTZsjkjsF1jRL4uSeqg==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Resources.ResourceManager", "4.3.0", "sha512-kGfbKPHEjQj8Uq1Apgj4jBStkRJkZ0Hdr0Jv3+aL7WGrAZVLF5Rh5h0Yc3FgDB5uXDbHiJk/WhBaZPVwKmuB1A==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Globalization", "System.Reflection", "System.Runtime"], []),
            ("System.Runtime", "4.3.1", "sha512-Al69mPDfzdD+bKGK2HAfB+lNFOHFqnkqzNnUJmmvUe1/qEPK9M7EiTT4zuycKDPy7ev11xz8XVgJWKP0hm7NIA==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets"], []),
            ("System.Runtime.CompilerServices.Unsafe", "6.0.0", "sha512-1AVzAb5OxJNvJLnOADtexNmWgattm2XVOT3TjQTN7Dd4SqoSwai1CsN2fth42uQldJSQdz/sAec0+TzxBFgisw==", [], []),
            ("System.Runtime.Extensions", "4.3.1", "sha512-VSbBNw3UQxuHk4aALPsYo154l+TKUR4Ij+Nj9GPnyJkzAmMewY1AyHXuaE+KCJ6JBj2SoO4uwLqY4ORKW9JRTw==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Runtime.Handles", "4.3.0", "sha512-CluvHdVUv54BvLTOCCyybugreDNk/rR8unMPruzXDtxSjvrQOU3M4R831/lQf4YI8VYp668FGQa/01E+Rq8PEQ==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Runtime.InteropServices", "4.3.0", "sha512-ZQeZw+ZU77ua1nFXycYM5G8oioFZe+N84qC/XUg1BEBl7z9luZcyjLu7+4H0yJuNfn1hOAiAAZ3u5us/lj9w2Q==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Reflection", "System.Reflection.Primitives", "System.Runtime", "System.Runtime.Handles"], []),
            ("System.Runtime.Numerics", "4.3.0", "sha512-PjR/qo5+xITUgeU7HCGf4c40augniiFLRQjPDiM8Fie9nGxsfGVOjB9BQycYON3ZWT9joQQ1d62HxA45Kvf9NA==", ["System.Globalization", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions"], []),
            ("System.Security.AccessControl", "6.0.0", "sha512-ZKNqEDuVSrS36KdsDodleb1ITDCOREwtkV+5oP0FrWNhRQHtI1xUSvybQxy4pM8PBxW47UFOhZWObWhXkWj7RQ==", [], []),
            ("System.Security.Cryptography.Algorithms", "4.3.1", "sha512-NLArYLaaVOExC1EVEuMhCkm/sFhMUPgLWcWG1xgK2XPjtUGfelV4ODeIQ5VGDbPg2xPI+yfebRcLjS2rHJCtzw==", ["Microsoft.NETCore.Platforms", "runtime.native.System.Security.Cryptography.Apple", "runtime.native.System.Security.Cryptography.OpenSsl", "System.Collections", "System.IO", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.Handles", "System.Runtime.InteropServices", "System.Runtime.Numerics", "System.Security.Cryptography.Encoding", "System.Security.Cryptography.Primitives", "System.Text.Encoding"], []),
            ("System.Security.Cryptography.Cng", "5.0.0", "sha512-trvkAklUhzM+/z9bPnGmDLzmbvD0l1IlC6gpFRpzjGLylTgtTPqm8Uv7tnDBTuBQObjEZBxNS0bChIi6zQCV9w==", ["System.Formats.Asn1"], []),
            ("System.Security.Cryptography.Csp", "4.3.0", "sha512-QzF1kXR6GPUvaDGH4Jrf4OA1c+baxDC/O6E/RAzbHHux+SBTadXzsqDz/flgTVuh5tlKiZol0sUz5FMzhXjzUQ==", ["Microsoft.NETCore.Platforms", "System.IO", "System.Reflection", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.Handles", "System.Runtime.InteropServices", "System.Security.Cryptography.Algorithms", "System.Security.Cryptography.Encoding", "System.Security.Cryptography.Primitives", "System.Text.Encoding", "System.Threading"], []),
            ("System.Security.Cryptography.Encoding", "4.3.0", "sha512-XCat0j5jVC83UG9fofcuiYDwN0PVKc2OWD0QVLjYpXn7dz+gNaANkHPbhNtr5PR8rDQNHrxtI912Hb29YAB14A==", ["Microsoft.NETCore.Platforms", "runtime.native.System.Security.Cryptography.OpenSsl", "System.Collections", "System.Collections.Concurrent", "System.Linq", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.Handles", "System.Runtime.InteropServices", "System.Security.Cryptography.Primitives", "System.Text.Encoding"], []),
            ("System.Security.Cryptography.OpenSsl", "5.0.0", "sha512-+8P4Eo9HMcke1V4bPK6JjBaHilI5MAYLcqPKVHcpbJmW3O6qOCxutBmEiuT3e6CZvk8cE4v2wqC5J3woxqEF/Q==", ["System.Formats.Asn1"], []),
            ("System.Security.Cryptography.Pkcs", "6.0.1", "sha512-ubxxZt0n9t8Xe/NtN53XMf6ZSfRKsk/T+mheDuoZbYrBJRLVyQ4pecXoROihl/DyC9uVOt6QrejwLAx1Raj1wg==", ["System.Formats.Asn1"], []),
            ("System.Security.Cryptography.Primitives", "4.3.0", "sha512-WtgnP5mOu5zKL3vQMUPT9tV7XVYGV7Jtb0540DgBD7MMN5ojonwIcw8VybZvS6VloGmE7CRt/Hms8adBsN1DRw==", ["System.Diagnostics.Debug", "System.Globalization", "System.IO", "System.Resources.ResourceManager", "System.Runtime", "System.Threading", "System.Threading.Tasks"], []),
            ("System.Security.Cryptography.ProtectedData", "6.0.0", "sha512-SJtdqwq/rfuLwtBDfeg6FEeRgHGUlEDnZttwHIHDUY3mo4o+D2mXBrBtWRq1OTx7wLLqqBwVv/FWM5JI5sNXMA==", [], []),
            ("System.Security.Cryptography.X509Certificates", "4.3.2", "sha512-Ax8SNsw9NCe5pBEysVjrPiGgmcw9ToUMQyNOsbKL0BAGO3VQ+Gis2eleJ7KVmJ5j2gFdgh42yc9U2hboXdy+3A==", ["Microsoft.NETCore.Platforms", "runtime.native.System", "runtime.native.System.Net.Http", "runtime.native.System.Security.Cryptography.OpenSsl", "System.Collections", "System.Diagnostics.Debug", "System.Globalization", "System.Globalization.Calendars", "System.IO", "System.IO.FileSystem", "System.IO.FileSystem.Primitives", "System.Resources.ResourceManager", "System.Runtime", "System.Runtime.Extensions", "System.Runtime.Handles", "System.Runtime.InteropServices", "System.Runtime.Numerics", "System.Security.Cryptography.Algorithms", "System.Security.Cryptography.Cng", "System.Security.Cryptography.Csp", "System.Security.Cryptography.Encoding", "System.Security.Cryptography.OpenSsl", "System.Security.Cryptography.Primitives", "System.Text.Encoding", "System.Threading"], []),
            ("System.Security.Permissions", "6.0.0", "sha512-1PIXLMOxZPEE+i46Mwti8qFfUOBQqRZZ21co8o1NXWyoZg7sOk+SIJAYGlS8Hp9mNMpJdQOYNgcn0bxZ22ICeA==", ["System.Security.AccessControl", "System.Windows.Extensions"], []),
            ("System.Text.Encoding", "4.3.0", "sha512-b/f+7HMTpxIfeV7H03bkuHKMFylCGfr9/U6gePnfFFW0aF8LOWLDgQCY6V1oWUqDksC3mdNuyChM1vy9TP4sZw==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Text.Json", "5.0.2", "sha512-PTL4h2MLbKEqZ/9TE6SEmJp1txIh0GjzYPQrWGbfJ5sgbPrpXzb9sOoXe3cid51zDBE+2KCLd95e/04JiNr0TQ==", [], []),
            ("System.Threading", "4.3.0", "sha512-l6J1G9zmn6r5xU+DSp/Vxgx6eG+qUvQgdpgo28m1gEwfNyG6HqlF6h2ESDXZCYEPnngsmkTQ+q7MyyMMTNlaiA==", ["System.Runtime", "System.Threading.Tasks"], []),
            ("System.Threading.Tasks", "4.3.0", "sha512-fUiP+CyyCjs872OA8trl6p97qma/da1xGq3h4zAbJZk8zyaU4zyEfqW5vbkP80xG/Nimun1vlWBboMEk7XxdEw==", ["Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets", "System.Runtime"], []),
            ("System.Windows.Extensions", "6.0.0", "sha512-9R7sgWb5e1/OokgW7HN8JNXFpcsUXvLTMnfJoWBE9AvD+5e0z+f5ojr3BO3pFYbGq9Ks8AsndTi7ME13ocpU8A==", ["System.Drawing.Common"], []),
        ],
    )
