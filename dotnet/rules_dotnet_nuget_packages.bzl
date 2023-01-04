"Generated by paket2bazel"

load("@rules_dotnet//dotnet:defs.bzl", "nuget_repo")

def rules_dotnet_nuget_packages():
    "rules_dotnet_nuget_packages"
    nuget_repo(
        name = "rules_dotnet_nuget_packages",
        packages = [
            ("McMaster.Extensions.CommandLineUtils", "2.5.0", "sha512-00uJOWYKPCPqDB6RxyOLXNnoPGeRmzKTZhu5OdZJaWn5+JV/n6mzB3/M+Z1yMpkabag3Lym9S11G/ITLrptOiw==", ["System.ComponentModel.Annotations"], []),
            ("Microsoft.NETCore.App.Ref", "7.0.1", "sha512-MgRWqOzOeDZ5A7z3j4kxpBb1/mQKG8jJY239/emtcGpw22gJa/kMV7LMm/lM9cSLcMfQl9EabD/dE+mSSEIseA==", [], ["Microsoft.CSharp|4.4.0", "Microsoft.Win32.Primitives|4.3.0", "Microsoft.Win32.Registry|4.4.0", "runtime.debian.8-x64.runtime.native.System|4.3.0", "runtime.debian.8-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.debian.8-x64.runtime.native.System.Net.Http|4.3.0", "runtime.debian.8-x64.runtime.native.System.Net.Security|4.3.0", "runtime.debian.8-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.debian.8-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.fedora.23-x64.runtime.native.System|4.3.0", "runtime.fedora.23-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Net.Http|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Net.Security|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.fedora.23-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.fedora.24-x64.runtime.native.System|4.3.0", "runtime.fedora.24-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Net.Http|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Net.Security|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.fedora.24-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Net.Http|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Net.Security|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.opensuse.13.2-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Net.Http|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Net.Security|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.opensuse.42.1-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.osx.10.10-x64.runtime.native.System|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Net.Http|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Net.Security|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.Apple|4.3.0", "runtime.osx.10.10-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.rhel.7-x64.runtime.native.System|4.3.0", "runtime.rhel.7-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Net.Http|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Net.Security|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.rhel.7-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.14.04-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.16.04-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.IO.Compression|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Net.Http|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Net.Security|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography|4.3.0", "runtime.ubuntu.16.10-x64.runtime.native.System.Security.Cryptography.OpenSsl|4.3.0", "System.AppContext|4.3.0", "System.Buffers|4.4.0", "System.Collections|4.3.0", "System.Collections.Concurrent|4.3.0", "System.Collections.Immutable|1.4.0", "System.Collections.NonGeneric|4.3.0", "System.Collections.Specialized|4.3.0", "System.ComponentModel|4.3.0", "System.ComponentModel.EventBasedAsync|4.3.0", "System.ComponentModel.Primitives|4.3.0", "System.ComponentModel.TypeConverter|4.3.0", "System.Console|4.3.0", "System.Data.Common|4.3.0", "System.Diagnostics.Contracts|4.3.0", "System.Diagnostics.Debug|4.3.0", "System.Diagnostics.DiagnosticSource|4.4.0", "System.Diagnostics.FileVersionInfo|4.3.0", "System.Diagnostics.Process|4.3.0", "System.Diagnostics.StackTrace|4.3.0", "System.Diagnostics.TextWriterTraceListener|4.3.0", "System.Diagnostics.Tools|4.3.0", "System.Diagnostics.TraceSource|4.3.0", "System.Diagnostics.Tracing|4.3.0", "System.Dynamic.Runtime|4.3.0", "System.Globalization|4.3.0", "System.Globalization.Calendars|4.3.0", "System.Globalization.Extensions|4.3.0", "System.IO|4.3.0", "System.IO.Compression|4.3.0", "System.IO.Compression.ZipFile|4.3.0", "System.IO.FileSystem|4.3.0", "System.IO.FileSystem.AccessControl|4.4.0", "System.IO.FileSystem.DriveInfo|4.3.0", "System.IO.FileSystem.Primitives|4.3.0", "System.IO.FileSystem.Watcher|4.3.0", "System.IO.IsolatedStorage|4.3.0", "System.IO.MemoryMappedFiles|4.3.0", "System.IO.Pipes|4.3.0", "System.IO.UnmanagedMemoryStream|4.3.0", "System.Linq|4.3.0", "System.Linq.Expressions|4.3.0", "System.Linq.Queryable|4.3.0", "System.Net.Http|4.3.0", "System.Net.NameResolution|4.3.0", "System.Net.Primitives|4.3.0", "System.Net.Requests|4.3.0", "System.Net.Security|4.3.0", "System.Net.Sockets|4.3.0", "System.Net.WebHeaderCollection|4.3.0", "System.ObjectModel|4.3.0", "System.Private.DataContractSerialization|4.3.0", "System.Reflection|4.3.0", "System.Reflection.Emit|4.3.0", "System.Reflection.Emit.ILGeneration|4.3.0", "System.Reflection.Emit.Lightweight|4.3.0", "System.Reflection.Extensions|4.3.0", "System.Reflection.Metadata|1.5.0", "System.Reflection.Primitives|4.3.0", "System.Reflection.TypeExtensions|4.3.0", "System.Resources.ResourceManager|4.3.0", "System.Runtime|4.3.0", "System.Runtime.Extensions|4.3.0", "System.Runtime.Handles|4.3.0", "System.Runtime.InteropServices|4.3.0", "System.Runtime.InteropServices.RuntimeInformation|4.3.0", "System.Runtime.Loader|4.3.0", "System.Runtime.Numerics|4.3.0", "System.Runtime.Serialization.Formatters|4.3.0", "System.Runtime.Serialization.Json|4.3.0", "System.Runtime.Serialization.Primitives|4.3.0", "System.Security.AccessControl|4.4.0", "System.Security.Claims|4.3.0", "System.Security.Cryptography.Algorithms|4.3.0", "System.Security.Cryptography.Cng|4.4.0", "System.Security.Cryptography.Csp|4.3.0", "System.Security.Cryptography.Encoding|4.3.0", "System.Security.Cryptography.OpenSsl|4.4.0", "System.Security.Cryptography.Primitives|4.3.0", "System.Security.Cryptography.X509Certificates|4.3.0", "System.Security.Cryptography.Xml|4.4.0", "System.Security.Principal|4.3.0", "System.Security.Principal.Windows|4.4.0", "System.Text.Encoding|4.3.0", "System.Text.Encoding.Extensions|4.3.0", "System.Text.RegularExpressions|4.3.0", "System.Threading|4.3.0", "System.Threading.Overlapped|4.3.0", "System.Threading.Tasks|4.3.0", "System.Threading.Tasks.Extensions|4.3.0", "System.Threading.Tasks.Parallel|4.3.0", "System.Threading.Thread|4.3.0", "System.Threading.ThreadPool|4.3.0", "System.Threading.Timer|4.3.0", "System.ValueTuple|4.3.0", "System.Xml.ReaderWriter|4.3.0", "System.Xml.XDocument|4.3.0", "System.Xml.XmlDocument|4.3.0", "System.Xml.XmlSerializer|4.3.0", "System.Xml.XPath|4.3.0", "System.Xml.XPath.XDocument|4.3.0"]),
            ("Microsoft.NETCore.Platforms", "6.0.5", "sha512-GTMT/dgCRBCRUj11ssZ8K1FJm6Md+C/tSJl8I7YjxOFwSvopaIneV32y1VlnBTI4wy1SwueI7ou2sVfHkWENrA==", [], []),
            ("Microsoft.Web.Xdt", "3.1.0", "sha512-3VApgkdgOglJWtrXSgYzz6o8Cp6IpvmFQMeICyQvvbKoy+OjNwco5ovzBBL1HHj7kEgLfe2ruXW/ZQ1k+2YxYw==", [], []),
            ("NETStandard.Library", "2.0.3", "sha512-548M6mnBSJWxsIlkQHfbzoYxpiYFXZZSL00p4GHYv8PkiqFBnnT68mW5mGEsA/ch9fDO9GkPgkFQpWiXZN7mAQ==", ["Microsoft.NETCore.Platforms"], []),
            ("NETStandard.Library.Ref", "2.1.0", "sha512-Jr0OqnqkaJJGEVq3w9oNQrIEteD/4QBNg3YOh1cvRjydzwop07+5aWjO/SfEYu6CwBn+dSBKXj8niEvTNy2brA==", [], ["Microsoft.Win32.Primitives|4.3.0", "System.AppContext|4.3.0", "System.Collections|4.3.0", "System.Collections.Concurrent|4.3.0", "System.Collections.Immutable|1.4.0", "System.Collections.NonGeneric|4.3.0", "System.Collections.Specialized|4.3.0", "System.ComponentModel|4.3.0", "System.ComponentModel.EventBasedAsync|4.3.0", "System.ComponentModel.Primitives|4.3.0", "System.ComponentModel.TypeConverter|4.3.0", "System.Console|4.3.0", "System.Data.Common|4.3.0", "System.Diagnostics.Contracts|4.3.0", "System.Diagnostics.Debug|4.3.0", "System.Diagnostics.FileVersionInfo|4.3.0", "System.Diagnostics.Process|4.3.0", "System.Diagnostics.StackTrace|4.3.0", "System.Diagnostics.TextWriterTraceListener|4.3.0", "System.Diagnostics.Tools|4.3.0", "System.Diagnostics.TraceSource|4.3.0", "System.Diagnostics.Tracing|4.3.0", "System.Dynamic.Runtime|4.3.0", "System.Globalization|4.3.0", "System.Globalization.Calendars|4.3.0", "System.Globalization.Extensions|4.3.0", "System.IO|4.3.0", "System.IO.Compression|4.3.0", "System.IO.Compression.ZipFile|4.3.0", "System.IO.FileSystem|4.3.0", "System.IO.FileSystem.DriveInfo|4.3.0", "System.IO.FileSystem.Primitives|4.3.0", "System.IO.FileSystem.Watcher|4.3.0", "System.IO.IsolatedStorage|4.3.0", "System.IO.MemoryMappedFiles|4.3.0", "System.IO.Pipes|4.3.0", "System.IO.UnmanagedMemoryStream|4.3.0", "System.Linq|4.3.0", "System.Linq.Expressions|4.3.0", "System.Linq.Queryable|4.3.0", "System.Net.Http|4.3.0", "System.Net.NameResolution|4.3.0", "System.Net.Primitives|4.3.0", "System.Net.Requests|4.3.0", "System.Net.Security|4.3.0", "System.Net.Sockets|4.3.0", "System.Net.WebHeaderCollection|4.3.0", "System.ObjectModel|4.3.0", "System.Private.DataContractSerialization|4.3.0", "System.Reflection|4.3.0", "System.Reflection.Emit|4.3.0", "System.Reflection.Emit.ILGeneration|4.3.0", "System.Reflection.Emit.Lightweight|4.3.0", "System.Reflection.Extensions|4.3.0", "System.Reflection.Primitives|4.3.0", "System.Reflection.TypeExtensions|4.3.0", "System.Resources.ResourceManager|4.3.0", "System.Runtime|4.3.0", "System.Runtime.Extensions|4.3.0", "System.Runtime.Handles|4.3.0", "System.Runtime.InteropServices|4.3.0", "System.Runtime.InteropServices.RuntimeInformation|4.3.0", "System.Runtime.Loader|4.3.0", "System.Runtime.Numerics|4.3.0", "System.Runtime.Serialization.Formatters|4.3.0", "System.Runtime.Serialization.Json|4.3.0", "System.Runtime.Serialization.Primitives|4.3.0", "System.Security.AccessControl|4.4.0", "System.Security.Claims|4.3.0", "System.Security.Cryptography.Algorithms|4.3.0", "System.Security.Cryptography.Csp|4.3.0", "System.Security.Cryptography.Encoding|4.3.0", "System.Security.Cryptography.Primitives|4.3.0", "System.Security.Cryptography.X509Certificates|4.3.0", "System.Security.Cryptography.Xml|4.4.0", "System.Security.Principal|4.3.0", "System.Security.Principal.Windows|4.4.0", "System.Text.Encoding|4.3.0", "System.Text.Encoding.Extensions|4.3.0", "System.Text.RegularExpressions|4.3.0", "System.Threading|4.3.0", "System.Threading.Overlapped|4.3.0", "System.Threading.Tasks|4.3.0", "System.Threading.Tasks.Extensions|4.3.0", "System.Threading.Tasks.Parallel|4.3.0", "System.Threading.Thread|4.3.0", "System.Threading.ThreadPool|4.3.0", "System.Threading.Timer|4.3.0", "System.ValueTuple|4.3.0", "System.Xml.ReaderWriter|4.3.0", "System.Xml.XDocument|4.3.0", "System.Xml.XmlDocument|4.3.0", "System.Xml.XmlSerializer|4.3.0", "System.Xml.XPath|4.3.0", "System.Xml.XPath.XDocument|4.3.0"]),
            ("Newtonsoft.Json", "13.0.1", "sha512-g3MbZi6vBTeaI/hEbvR7vBETSd1DWLe9i1E4P+nPY34v5i94zqUqDXvdWC3G+7tYN9SnsdU9zzegrnRz4h7nsQ==", [], []),
            ("NuGet.Commands", "5.10.0", "sha512-Q7ANXnmLUPC4pWgCZjBy2R7vRDABiaJz5NsBtoErE0dLylx/zQWRMyoa+m4Y478SKvUpt7S1V7LhAOlMRCTPpg==", ["NuGet.Credentials", "NuGet.ProjectModel"], []),
            ("NuGet.Common", "5.10.0", "sha512-8M9VtXAB1M15KmvL0F9QsItI96PH3WmYD0z3oxYm5H9G5AIhK8Ivi4kGzqtBJDTsZ/NkP91U1MnoCAeg4E4+zA==", ["NuGet.Frameworks"], []),
            ("NuGet.Configuration", "5.10.0", "sha512-ZJc2HY/D+UEk2U0jxamyBhUbKl2bgluViM/tnP4ObIIfJpOj8dHEJ6xzggulIGDlhe+ItK6yc+sqtCb6qV5+gw==", ["NuGet.Common", "System.Security.Cryptography.ProtectedData"], []),
            ("NuGet.Credentials", "5.10.0", "sha512-r/fzn5yJaCXyChbhxbGZ5d/4xV4n3NIjVdE3odLfQy0znmcYRCDIfjYGu5l7vO9Nx27F+q7YA+9QmG9sucxX9A==", ["NuGet.Protocol"], []),
            ("NuGet.DependencyResolver.Core", "5.10.0", "sha512-+9mCFiBhnm5C2Cb3dtHaHyv/WarSr5HwRi2NaoVJgudpHoK3B9uy8wB7PNnUos0kOghZmVslemeLsmw7icQqTw==", ["NuGet.LibraryModel", "NuGet.Protocol"], []),
            ("NuGet.Frameworks", "5.10.0", "sha512-l8KtHN2bzA391seLZ9Q2AWK0mbCHpfbwL1nmOSMDxBpWLxqh+nxMWaKL437bROpHltU+oP5LX/hc4Fxm89T9Tg==", [], []),
            ("NuGet.LibraryModel", "5.10.0", "sha512-xb8XLKJEMymZMAZJeXdSUaDNFRQMJ4MXkOPUaqafcgSKGz8M8BZgfLsBz9QCQVEyHIVYGbI4yroWZYed/c8xSg==", ["NuGet.Common", "NuGet.Versioning"], []),
            ("NuGet.PackageManagement", "5.10.0", "sha512-Kr0CZuStXNsJRL86ecuWGhIHUhYy31rYZJ9WZ0tiFUaRwiPb7HpSQVsV/v3tqrKE7FWUZBpasX1bugXNqXcPjA==", ["NuGet.Commands", "NuGet.Resolver", "Microsoft.Web.Xdt", "System.ComponentModel.Composition"], []),
            ("Nuget.Packaging", "5.10.0", "sha512-2HMq5gNgLMOHmqGb84pyEC7ctkCYBVXkhJfcYmHlkpo4FpDA6GQBoT//1h0Q4nGoybtgoBxiIbJu8VRn/9CZrQ==", ["NuGet.Configuration", "NuGet.Versioning", "Newtonsoft.Json", "System.Security.Cryptography.Cng", "System.Security.Cryptography.Pkcs"], []),
            ("Nuget.Packaging.Core", "5.10.0", "sha512-/WXGAbLb4T0pwEfEeY0j8zOVpS36OHNUANL95txANysbLoG7tUr9e+5je+Nfh3iIqzMaHIZXT6JKFvHOBwAotw==", [], []),
            ("NuGet.ProjectModel", "5.10.0", "sha512-gsZS2Kuat3ZjjPcBQ3Mc8QlRv6mP1OzNzkF4Dzybu3LgtG+kwvgQh4UMLbiIrko6WKbwVTbr8nQYpL+wsVZ4hA==", ["NuGet.DependencyResolver.Core"], []),
            ("NuGet.Protocol", "5.10.0", "sha512-lY85Pgf7kr0JwTufdJmfDgBwN9BRQc96F4xxKrUGSALhuZRRC7y6f2RN1JQ0UTPIXlQx7HTG/h0UZEknQj3/UQ==", [], []),
            ("NuGet.Resolver", "5.10.0", "sha512-a2zWl9RkKDkcVUqfRJjz3O4uoPIWf3PGaFf6AntXtTKjvvsB6SZz8jjPSGdLgTTRIWzsFlybKp6yU+GaXeIQkg==", ["NuGet.Protocol"], []),
            ("NuGet.Versioning", "5.10.0", "sha512-NW11tfXijCWeI8d71HKpNPKPzJqr30PtUyJHzCpKFMFTGZhsHh2YxgjKBuhpC5R59SMZUzqrFF5CgJ8uGaupqg==", [], []),
            ("NUnit", "3.12.0", "sha512-HAhwFxr+Z+PJf8hXzc747NecvsDwEZ+3X8SA5+GIRM43GAy1Ap+TQPMHsWCnisfes5vPZ1/a2md/91u+shoTsQ==", ["NETStandard.Library"], []),
            ("NUnitLite", "3.12.0", "sha512-M9VVS4x3KURXFS4HTl2b7uJOX7vOi2wzpHACmNX6ANlBmb0/hIehJLciiVvddD3ubIIL81EF4Qk54kpsUOtVFQ==", ["NUnit", "NETStandard.Library"], []),
            ("System.ComponentModel.Annotations", "5.0.0", "sha512-WJqsTGaXAc55EPGjJylPFXiNPs/x1t9dklVlHlIBxUEcIxIob6sRGm9Un7TehkyEFM+vKjZd7rbwaMH/znw1PA==", [], []),
            ("System.ComponentModel.Composition", "6.0.0", "sha512-YWQ3ENu0D2st9ZV+Yj4u3IFcas0Pw7S4c7ymDUooPLb1psNJ53YniX2orSiY2OlRWnssaUsTytnVJa/KfCn5aA==", [], []),
            ("System.Formats.Asn1", "6.0.0", "sha512-62YP6zLnvmFtFI3rjybbrnSeK6hHQCaFfJJfoNhQqrETJBPehSucQxIyQs5W+GGBW/rpSXD/0NqNW7mttIWXhA==", [], []),
            ("System.Security.Cryptography.Cng", "5.0.0", "sha512-trvkAklUhzM+/z9bPnGmDLzmbvD0l1IlC6gpFRpzjGLylTgtTPqm8Uv7tnDBTuBQObjEZBxNS0bChIi6zQCV9w==", ["System.Formats.Asn1"], []),
            ("System.Security.Cryptography.Pkcs", "6.0.1", "sha512-ubxxZt0n9t8Xe/NtN53XMf6ZSfRKsk/T+mheDuoZbYrBJRLVyQ4pecXoROihl/DyC9uVOt6QrejwLAx1Raj1wg==", ["System.Formats.Asn1"], []),
            ("System.Security.Cryptography.ProtectedData", "6.0.0", "sha512-SJtdqwq/rfuLwtBDfeg6FEeRgHGUlEDnZttwHIHDUY3mo4o+D2mXBrBtWRq1OTx7wLLqqBwVv/FWM5JI5sNXMA==", [], []),
        ],
    )
