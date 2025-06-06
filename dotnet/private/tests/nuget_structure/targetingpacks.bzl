"NuGet structure tests"

load(
    "//dotnet/private/tests/nuget_structure:common.bzl",
    "nuget_framework_list_test",
    "nuget_structure_test",
    "nuget_targeting_pack_overrides_test",
    "nuget_test_wrapper",
)

# buildifier: disable=unnamed-macro
def targetingpacks_structure():
    "Tests for parsing of targeting packs"
    nuget_test_wrapper(
        name = "microsoft.netframework.referenceassemblies.net48",
        target_framework = "net48",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//microsoft.netframework.referenceassemblies.net48",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_netframework_48_targetingpack_correctly",
        target_under_test = ":microsoft.netframework.referenceassemblies.net48",
        expected_refs = [
            "build/.NETFramework/v4.8/Accessibility.dll",
            "build/.NETFramework/v4.8/CustomMarshalers.dll",
            "build/.NETFramework/v4.8/Facades/Microsoft.Win32.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.AppContext.dll",
            "build/.NETFramework/v4.8/Facades/System.Collections.Concurrent.dll",
            "build/.NETFramework/v4.8/Facades/System.Collections.NonGeneric.dll",
            "build/.NETFramework/v4.8/Facades/System.Collections.Specialized.dll",
            "build/.NETFramework/v4.8/Facades/System.Collections.dll",
            "build/.NETFramework/v4.8/Facades/System.ComponentModel.Annotations.dll",
            "build/.NETFramework/v4.8/Facades/System.ComponentModel.EventBasedAsync.dll",
            "build/.NETFramework/v4.8/Facades/System.ComponentModel.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.ComponentModel.TypeConverter.dll",
            "build/.NETFramework/v4.8/Facades/System.ComponentModel.dll",
            "build/.NETFramework/v4.8/Facades/System.Console.dll",
            "build/.NETFramework/v4.8/Facades/System.Data.Common.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.Contracts.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.Debug.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.FileVersionInfo.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.Process.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.StackTrace.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.TextWriterTraceListener.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.Tools.dll",
            "build/.NETFramework/v4.8/Facades/System.Diagnostics.TraceSource.dll",
            "build/.NETFramework/v4.8/Facades/System.Drawing.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.Dynamic.Runtime.dll",
            "build/.NETFramework/v4.8/Facades/System.Globalization.Calendars.dll",
            "build/.NETFramework/v4.8/Facades/System.Globalization.Extensions.dll",
            "build/.NETFramework/v4.8/Facades/System.Globalization.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.Compression.ZipFile.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.FileSystem.DriveInfo.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.FileSystem.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.FileSystem.Watcher.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.FileSystem.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.IsolatedStorage.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.MemoryMappedFiles.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.Pipes.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.UnmanagedMemoryStream.dll",
            "build/.NETFramework/v4.8/Facades/System.IO.dll",
            "build/.NETFramework/v4.8/Facades/System.Linq.Expressions.dll",
            "build/.NETFramework/v4.8/Facades/System.Linq.Parallel.dll",
            "build/.NETFramework/v4.8/Facades/System.Linq.Queryable.dll",
            "build/.NETFramework/v4.8/Facades/System.Linq.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Http.Rtc.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.NameResolution.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.NetworkInformation.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Ping.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Requests.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Security.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.Sockets.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.WebHeaderCollection.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.WebSockets.Client.dll",
            "build/.NETFramework/v4.8/Facades/System.Net.WebSockets.dll",
            "build/.NETFramework/v4.8/Facades/System.ObjectModel.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.Emit.ILGeneration.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.Emit.Lightweight.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.Emit.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.Extensions.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.Reflection.dll",
            "build/.NETFramework/v4.8/Facades/System.Resources.Reader.dll",
            "build/.NETFramework/v4.8/Facades/System.Resources.ResourceManager.dll",
            "build/.NETFramework/v4.8/Facades/System.Resources.Writer.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.CompilerServices.VisualC.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Extensions.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Handles.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.InteropServices.RuntimeInformation.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.InteropServices.WindowsRuntime.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.InteropServices.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Numerics.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Serialization.Formatters.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Serialization.Json.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Serialization.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.Serialization.Xml.dll",
            "build/.NETFramework/v4.8/Facades/System.Runtime.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Claims.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Cryptography.Algorithms.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Cryptography.Csp.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Cryptography.Encoding.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Cryptography.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Cryptography.X509Certificates.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.Principal.dll",
            "build/.NETFramework/v4.8/Facades/System.Security.SecureString.dll",
            "build/.NETFramework/v4.8/Facades/System.ServiceModel.Duplex.dll",
            "build/.NETFramework/v4.8/Facades/System.ServiceModel.Http.dll",
            "build/.NETFramework/v4.8/Facades/System.ServiceModel.NetTcp.dll",
            "build/.NETFramework/v4.8/Facades/System.ServiceModel.Primitives.dll",
            "build/.NETFramework/v4.8/Facades/System.ServiceModel.Security.dll",
            "build/.NETFramework/v4.8/Facades/System.Text.Encoding.Extensions.dll",
            "build/.NETFramework/v4.8/Facades/System.Text.Encoding.dll",
            "build/.NETFramework/v4.8/Facades/System.Text.RegularExpressions.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.Overlapped.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.Tasks.Parallel.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.Tasks.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.Thread.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.ThreadPool.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.Timer.dll",
            "build/.NETFramework/v4.8/Facades/System.Threading.dll",
            "build/.NETFramework/v4.8/Facades/System.ValueTuple.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.ReaderWriter.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.XDocument.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.XPath.XDocument.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.XPath.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.XmlDocument.dll",
            "build/.NETFramework/v4.8/Facades/System.Xml.XmlSerializer.dll",
            "build/.NETFramework/v4.8/Facades/netstandard.dll",
            "build/.NETFramework/v4.8/ISymWrapper.dll",
            "build/.NETFramework/v4.8/Microsoft.Activities.Build.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.Conversion.v4.0.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.Engine.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.Framework.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.Tasks.v4.0.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.Utilities.v4.0.dll",
            "build/.NETFramework/v4.8/Microsoft.Build.dll",
            "build/.NETFramework/v4.8/Microsoft.CSharp.dll",
            "build/.NETFramework/v4.8/Microsoft.JScript.dll",
            "build/.NETFramework/v4.8/Microsoft.VisualBasic.Compatibility.Data.dll",
            "build/.NETFramework/v4.8/Microsoft.VisualBasic.Compatibility.dll",
            "build/.NETFramework/v4.8/Microsoft.VisualBasic.dll",
            "build/.NETFramework/v4.8/Microsoft.VisualC.STLCLR.dll",
            "build/.NETFramework/v4.8/Microsoft.VisualC.dll",
            "build/.NETFramework/v4.8/PresentationBuildTasks.dll",
            "build/.NETFramework/v4.8/PresentationCore.dll",
            "build/.NETFramework/v4.8/PresentationFramework.Aero.dll",
            "build/.NETFramework/v4.8/PresentationFramework.Aero2.dll",
            "build/.NETFramework/v4.8/PresentationFramework.AeroLite.dll",
            "build/.NETFramework/v4.8/PresentationFramework.Classic.dll",
            "build/.NETFramework/v4.8/PresentationFramework.Luna.dll",
            "build/.NETFramework/v4.8/PresentationFramework.Royale.dll",
            "build/.NETFramework/v4.8/PresentationFramework.dll",
            "build/.NETFramework/v4.8/ReachFramework.dll",
            "build/.NETFramework/v4.8/System.Activities.Core.Presentation.dll",
            "build/.NETFramework/v4.8/System.Activities.DurableInstancing.dll",
            "build/.NETFramework/v4.8/System.Activities.Presentation.dll",
            "build/.NETFramework/v4.8/System.Activities.dll",
            "build/.NETFramework/v4.8/System.AddIn.Contract.dll",
            "build/.NETFramework/v4.8/System.AddIn.dll",
            "build/.NETFramework/v4.8/System.ComponentModel.Composition.Registration.dll",
            "build/.NETFramework/v4.8/System.ComponentModel.Composition.dll",
            "build/.NETFramework/v4.8/System.ComponentModel.DataAnnotations.dll",
            "build/.NETFramework/v4.8/System.Configuration.Install.dll",
            "build/.NETFramework/v4.8/System.Configuration.dll",
            "build/.NETFramework/v4.8/System.Core.dll",
            "build/.NETFramework/v4.8/System.Data.DataSetExtensions.dll",
            "build/.NETFramework/v4.8/System.Data.Entity.Design.dll",
            "build/.NETFramework/v4.8/System.Data.Entity.dll",
            "build/.NETFramework/v4.8/System.Data.Linq.dll",
            "build/.NETFramework/v4.8/System.Data.OracleClient.dll",
            "build/.NETFramework/v4.8/System.Data.Services.Client.dll",
            "build/.NETFramework/v4.8/System.Data.Services.Design.dll",
            "build/.NETFramework/v4.8/System.Data.Services.dll",
            "build/.NETFramework/v4.8/System.Data.SqlXml.dll",
            "build/.NETFramework/v4.8/System.Data.dll",
            "build/.NETFramework/v4.8/System.Deployment.dll",
            "build/.NETFramework/v4.8/System.Design.dll",
            "build/.NETFramework/v4.8/System.Device.dll",
            "build/.NETFramework/v4.8/System.Diagnostics.Tracing.dll",
            "build/.NETFramework/v4.8/System.DirectoryServices.AccountManagement.dll",
            "build/.NETFramework/v4.8/System.DirectoryServices.Protocols.dll",
            "build/.NETFramework/v4.8/System.DirectoryServices.dll",
            "build/.NETFramework/v4.8/System.Drawing.Design.dll",
            "build/.NETFramework/v4.8/System.Drawing.dll",
            "build/.NETFramework/v4.8/System.Dynamic.dll",
            "build/.NETFramework/v4.8/System.EnterpriseServices.dll",
            "build/.NETFramework/v4.8/System.IO.Compression.FileSystem.dll",
            "build/.NETFramework/v4.8/System.IO.Compression.dll",
            "build/.NETFramework/v4.8/System.IO.Log.dll",
            "build/.NETFramework/v4.8/System.IdentityModel.Selectors.dll",
            "build/.NETFramework/v4.8/System.IdentityModel.Services.dll",
            "build/.NETFramework/v4.8/System.IdentityModel.dll",
            "build/.NETFramework/v4.8/System.Management.Instrumentation.dll",
            "build/.NETFramework/v4.8/System.Management.dll",
            "build/.NETFramework/v4.8/System.Messaging.dll",
            "build/.NETFramework/v4.8/System.Net.Http.WebRequest.dll",
            "build/.NETFramework/v4.8/System.Net.Http.dll",
            "build/.NETFramework/v4.8/System.Net.dll",
            "build/.NETFramework/v4.8/System.Numerics.dll",
            "build/.NETFramework/v4.8/System.Printing.dll",
            "build/.NETFramework/v4.8/System.Reflection.Context.dll",
            "build/.NETFramework/v4.8/System.Runtime.Caching.dll",
            "build/.NETFramework/v4.8/System.Runtime.DurableInstancing.dll",
            "build/.NETFramework/v4.8/System.Runtime.Remoting.dll",
            "build/.NETFramework/v4.8/System.Runtime.Serialization.Formatters.Soap.dll",
            "build/.NETFramework/v4.8/System.Runtime.Serialization.dll",
            "build/.NETFramework/v4.8/System.Security.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Activation.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Activities.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Channels.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Discovery.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Routing.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.Web.dll",
            "build/.NETFramework/v4.8/System.ServiceModel.dll",
            "build/.NETFramework/v4.8/System.ServiceProcess.dll",
            "build/.NETFramework/v4.8/System.Speech.dll",
            "build/.NETFramework/v4.8/System.Transactions.dll",
            "build/.NETFramework/v4.8/System.Web.Abstractions.dll",
            "build/.NETFramework/v4.8/System.Web.ApplicationServices.dll",
            "build/.NETFramework/v4.8/System.Web.DataVisualization.Design.dll",
            "build/.NETFramework/v4.8/System.Web.DataVisualization.dll",
            "build/.NETFramework/v4.8/System.Web.DynamicData.Design.dll",
            "build/.NETFramework/v4.8/System.Web.DynamicData.dll",
            "build/.NETFramework/v4.8/System.Web.Entity.Design.dll",
            "build/.NETFramework/v4.8/System.Web.Entity.dll",
            "build/.NETFramework/v4.8/System.Web.Extensions.Design.dll",
            "build/.NETFramework/v4.8/System.Web.Extensions.dll",
            "build/.NETFramework/v4.8/System.Web.Mobile.dll",
            "build/.NETFramework/v4.8/System.Web.RegularExpressions.dll",
            "build/.NETFramework/v4.8/System.Web.Routing.dll",
            "build/.NETFramework/v4.8/System.Web.Services.dll",
            "build/.NETFramework/v4.8/System.Web.dll",
            "build/.NETFramework/v4.8/System.Windows.Controls.Ribbon.dll",
            "build/.NETFramework/v4.8/System.Windows.Forms.DataVisualization.Design.dll",
            "build/.NETFramework/v4.8/System.Windows.Forms.DataVisualization.dll",
            "build/.NETFramework/v4.8/System.Windows.Forms.dll",
            "build/.NETFramework/v4.8/System.Windows.Input.Manipulations.dll",
            "build/.NETFramework/v4.8/System.Windows.Presentation.dll",
            "build/.NETFramework/v4.8/System.Windows.dll",
            "build/.NETFramework/v4.8/System.Workflow.Activities.dll",
            "build/.NETFramework/v4.8/System.Workflow.ComponentModel.dll",
            "build/.NETFramework/v4.8/System.Workflow.Runtime.dll",
            "build/.NETFramework/v4.8/System.WorkflowServices.dll",
            "build/.NETFramework/v4.8/System.Xaml.dll",
            "build/.NETFramework/v4.8/System.Xml.Linq.dll",
            "build/.NETFramework/v4.8/System.Xml.Serialization.dll",
            "build/.NETFramework/v4.8/System.Xml.dll",
            "build/.NETFramework/v4.8/System.dll",
            "build/.NETFramework/v4.8/UIAutomationClient.dll",
            "build/.NETFramework/v4.8/UIAutomationClientsideProviders.dll",
            "build/.NETFramework/v4.8/UIAutomationProvider.dll",
            "build/.NETFramework/v4.8/UIAutomationTypes.dll",
            "build/.NETFramework/v4.8/WindowsBase.dll",
            "build/.NETFramework/v4.8/WindowsFormsIntegration.dll",
            "build/.NETFramework/v4.8/XamlBuildTask.dll",
            "build/.NETFramework/v4.8/mscorlib.dll",
            "build/.NETFramework/v4.8/sysglobl.dll",
        ],
    )

    nuget_test_wrapper(
        name = "microsoft.aspnetcore.app.ref.v8.0.16",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@dotnet.targeting_packs//microsoft.aspnetcore.app.ref.v8.0.16",
    )

    # This test is to ensure that different targeting packs in the same repo do not override each other.
    # Previously, newer versions like microsoft.aspnetcore.app.ref.v9.0.x would override the targeting packs
    # of older versions, which caused issues when targeting older TFMs.
    nuget_targeting_pack_overrides_test(
        name = "nuget_targeting_pack_overrides_different_targeting_pack_overrides_in_the_same_repo_should_not_override_each_other",
        target_under_test = ":microsoft.aspnetcore.app.ref.v8.0.16",
        expected_targeting_pack_overrides = {
            "microsoft.extensions.caching.abstractions": "8.0.0",
            "microsoft.extensions.caching.memory": "8.0.0",
            "microsoft.extensions.configuration.abstractions": "8.0.0",
            "microsoft.extensions.configuration.binder": "8.0.0",
            "microsoft.extensions.configuration.commandline": "8.0.0",
            "microsoft.extensions.configuration": "8.0.0",
            "microsoft.extensions.configuration.environmentvariables": "8.0.0",
            "microsoft.extensions.configuration.fileextensions": "8.0.0",
            "microsoft.extensions.configuration.ini": "8.0.0",
            "microsoft.extensions.configuration.json": "8.0.0",
            "microsoft.extensions.configuration.usersecrets": "8.0.0",
            "microsoft.extensions.configuration.xml": "8.0.0",
            "microsoft.extensions.dependencyinjection.abstractions": "8.0.0",
            "microsoft.extensions.dependencyinjection": "8.0.0",
            "microsoft.extensions.diagnostics.abstractions": "8.0.0",
            "microsoft.extensions.diagnostics": "8.0.0",
            "microsoft.extensions.fileproviders.abstractions": "8.0.0",
            "microsoft.extensions.fileproviders.composite": "8.0.0",
            "microsoft.extensions.fileproviders.physical": "8.0.0",
            "microsoft.extensions.filesystemglobbing": "8.0.0",
            "microsoft.extensions.hosting.abstractions": "8.0.0",
            "microsoft.extensions.hosting": "8.0.0",
            "microsoft.extensions.http": "8.0.0",
            "microsoft.extensions.logging.abstractions": "8.0.0",
            "microsoft.extensions.logging.configuration": "8.0.0",
            "microsoft.extensions.logging.console": "8.0.0",
            "microsoft.extensions.logging.debug": "8.0.0",
            "microsoft.extensions.logging": "8.0.0",
            "microsoft.extensions.logging.eventlog": "8.0.0",
            "microsoft.extensions.logging.eventsource": "8.0.0",
            "microsoft.extensions.logging.tracesource": "8.0.0",
            "microsoft.extensions.options.configurationextensions": "8.0.0",
            "microsoft.extensions.options.dataannotations": "8.0.0",
            "microsoft.extensions.options": "8.0.0",
            "microsoft.extensions.primitives": "8.0.0",
            "system.diagnostics.eventlog": "8.0.0",
            "system.io.pipelines": "8.0.0",
            "system.security.cryptography.xml": "8.0.0",
            "system.threading.ratelimiting": "8.0.0",
            "microsoft.aspnetcore.antiforgery": "8.0.0",
            "microsoft.aspnetcore.authentication.abstractions": "8.0.0",
            "microsoft.aspnetcore.authentication.bearertoken": "8.0.0",
            "microsoft.aspnetcore.authentication.cookies": "8.0.0",
            "microsoft.aspnetcore.authentication.core": "8.0.0",
            "microsoft.aspnetcore.authentication": "8.0.0",
            "microsoft.aspnetcore.authentication.oauth": "8.0.0",
            "microsoft.aspnetcore.authorization": "8.0.0",
            "microsoft.aspnetcore.authorization.policy": "8.0.0",
            "microsoft.aspnetcore.components.authorization": "8.0.0",
            "microsoft.aspnetcore.components": "8.0.0",
            "microsoft.aspnetcore.components.endpoints": "8.0.0",
            "microsoft.aspnetcore.components.forms": "8.0.0",
            "microsoft.aspnetcore.components.server": "8.0.0",
            "microsoft.aspnetcore.components.web": "8.0.0",
            "microsoft.aspnetcore.connections.abstractions": "8.0.0",
            "microsoft.aspnetcore.cookiepolicy": "8.0.0",
            "microsoft.aspnetcore.cors": "8.0.0",
            "microsoft.aspnetcore.cryptography.internal": "8.0.0",
            "microsoft.aspnetcore.cryptography.keyderivation": "8.0.0",
            "microsoft.aspnetcore.dataprotection.abstractions": "8.0.0",
            "microsoft.aspnetcore.dataprotection": "8.0.0",
            "microsoft.aspnetcore.dataprotection.extensions": "8.0.0",
            "microsoft.aspnetcore.diagnostics.abstractions": "8.0.0",
            "microsoft.aspnetcore.diagnostics": "8.0.0",
            "microsoft.aspnetcore.diagnostics.healthchecks": "8.0.0",
            "microsoft.aspnetcore": "8.0.0",
            "microsoft.aspnetcore.hostfiltering": "8.0.0",
            "microsoft.aspnetcore.hosting.abstractions": "8.0.0",
            "microsoft.aspnetcore.hosting": "8.0.0",
            "microsoft.aspnetcore.hosting.server.abstractions": "8.0.0",
            "microsoft.aspnetcore.html.abstractions": "8.0.0",
            "microsoft.aspnetcore.http.abstractions": "8.0.0",
            "microsoft.aspnetcore.http.connections.common": "8.0.0",
            "microsoft.aspnetcore.http.connections": "8.0.0",
            "microsoft.aspnetcore.http": "8.0.0",
            "microsoft.aspnetcore.http.extensions": "8.0.0",
            "microsoft.aspnetcore.http.features": "8.0.0",
            "microsoft.aspnetcore.http.results": "8.0.0",
            "microsoft.aspnetcore.httplogging": "8.0.0",
            "microsoft.aspnetcore.httpoverrides": "8.0.0",
            "microsoft.aspnetcore.httpspolicy": "8.0.0",
            "microsoft.aspnetcore.identity": "8.0.0",
            "microsoft.aspnetcore.localization": "8.0.0",
            "microsoft.aspnetcore.localization.routing": "8.0.0",
            "microsoft.aspnetcore.metadata": "8.0.0",
            "microsoft.aspnetcore.mvc.abstractions": "8.0.0",
            "microsoft.aspnetcore.mvc.apiexplorer": "8.0.0",
            "microsoft.aspnetcore.mvc.core": "8.0.0",
            "microsoft.aspnetcore.mvc.cors": "8.0.0",
            "microsoft.aspnetcore.mvc.dataannotations": "8.0.0",
            "microsoft.aspnetcore.mvc": "8.0.0",
            "microsoft.aspnetcore.mvc.formatters.json": "8.0.0",
            "microsoft.aspnetcore.mvc.formatters.xml": "8.0.0",
            "microsoft.aspnetcore.mvc.localization": "8.0.0",
            "microsoft.aspnetcore.mvc.razor": "8.0.0",
            "microsoft.aspnetcore.mvc.razorpages": "8.0.0",
            "microsoft.aspnetcore.mvc.taghelpers": "8.0.0",
            "microsoft.aspnetcore.mvc.viewfeatures": "8.0.0",
            "microsoft.aspnetcore.outputcaching": "8.0.0",
            "microsoft.aspnetcore.ratelimiting": "8.0.0",
            "microsoft.aspnetcore.razor": "8.0.0",
            "microsoft.aspnetcore.razor.runtime": "8.0.0",
            "microsoft.aspnetcore.requestdecompression": "8.0.0",
            "microsoft.aspnetcore.responsecaching.abstractions": "8.0.0",
            "microsoft.aspnetcore.responsecaching": "8.0.0",
            "microsoft.aspnetcore.responsecompression": "8.0.0",
            "microsoft.aspnetcore.rewrite": "8.0.0",
            "microsoft.aspnetcore.routing.abstractions": "8.0.0",
            "microsoft.aspnetcore.routing": "8.0.0",
            "microsoft.aspnetcore.server.httpsys": "8.0.0",
            "microsoft.aspnetcore.server.iis": "8.0.0",
            "microsoft.aspnetcore.server.iisintegration": "8.0.0",
            "microsoft.aspnetcore.server.kestrel.core": "8.0.0",
            "microsoft.aspnetcore.server.kestrel": "8.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.namedpipes": "8.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.quic": "8.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.sockets": "8.0.0",
            "microsoft.aspnetcore.session": "8.0.0",
            "microsoft.aspnetcore.signalr.common": "8.0.0",
            "microsoft.aspnetcore.signalr.core": "8.0.0",
            "microsoft.aspnetcore.signalr": "8.0.0",
            "microsoft.aspnetcore.signalr.protocols.json": "8.0.0",
            "microsoft.aspnetcore.staticfiles": "8.0.0",
            "microsoft.aspnetcore.websockets": "8.0.0",
            "microsoft.aspnetcore.webutilities": "8.0.0",
            "microsoft.extensions.configuration.keyperfile": "8.0.0",
            "microsoft.extensions.diagnostics.healthchecks.abstractions": "8.0.0",
            "microsoft.extensions.diagnostics.healthchecks": "8.0.0",
            "microsoft.extensions.features": "8.0.0",
            "microsoft.extensions.fileproviders.embedded": "8.0.0",
            "microsoft.extensions.identity.core": "8.0.0",
            "microsoft.extensions.identity.stores": "8.0.0",
            "microsoft.extensions.localization.abstractions": "8.0.0",
            "microsoft.extensions.localization": "8.0.0",
            "microsoft.extensions.objectpool": "8.0.0",
            "microsoft.extensions.webencoders": "8.0.0",
            "microsoft.jsinterop": "8.0.0",
            "microsoft.net.http.headers": "8.0.0",
        },
    )

    nuget_framework_list_test(
        name = "nuget_framework_list_different_framework_lists_in_the_same_repo_should_not_override_each_other",
        target_under_test = ":microsoft.aspnetcore.app.ref.v8.0.16",
        expected_framework_list = {
            "microsoft.aspnetcore.antiforgery": "8.0.0.0",
            "microsoft.aspnetcore.authentication.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.authentication.bearertoken": "8.0.0.0",
            "microsoft.aspnetcore.authentication.cookies": "8.0.0.0",
            "microsoft.aspnetcore.authentication.core": "8.0.0.0",
            "microsoft.aspnetcore.authentication.oauth": "8.0.0.0",
            "microsoft.aspnetcore.authentication": "8.0.0.0",
            "microsoft.aspnetcore.authorization.policy": "8.0.0.0",
            "microsoft.aspnetcore.authorization": "8.0.0.0",
            "microsoft.aspnetcore.components.authorization": "8.0.0.0",
            "microsoft.aspnetcore.components.endpoints": "8.0.0.0",
            "microsoft.aspnetcore.components.forms": "8.0.0.0",
            "microsoft.aspnetcore.components.server": "8.0.0.0",
            "microsoft.aspnetcore.components.web": "8.0.0.0",
            "microsoft.aspnetcore.components": "8.0.0.0",
            "microsoft.aspnetcore.connections.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.cookiepolicy": "8.0.0.0",
            "microsoft.aspnetcore.cors": "8.0.0.0",
            "microsoft.aspnetcore.cryptography.internal": "8.0.0.0",
            "microsoft.aspnetcore.cryptography.keyderivation": "8.0.0.0",
            "microsoft.aspnetcore.dataprotection.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.dataprotection.extensions": "8.0.0.0",
            "microsoft.aspnetcore.dataprotection": "8.0.0.0",
            "microsoft.aspnetcore.diagnostics.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.diagnostics.healthchecks": "8.0.0.0",
            "microsoft.aspnetcore.diagnostics": "8.0.0.0",
            "microsoft.aspnetcore.hostfiltering": "8.0.0.0",
            "microsoft.aspnetcore.hosting.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.hosting.server.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.hosting": "8.0.0.0",
            "microsoft.aspnetcore.html.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.http.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.http.connections.common": "8.0.0.0",
            "microsoft.aspnetcore.http.connections": "8.0.0.0",
            "microsoft.aspnetcore.http.extensions": "8.0.0.0",
            "microsoft.aspnetcore.http.features": "8.0.0.0",
            "microsoft.aspnetcore.http.results": "8.0.0.0",
            "microsoft.aspnetcore.http": "8.0.0.0",
            "microsoft.aspnetcore.httplogging": "8.0.0.0",
            "microsoft.aspnetcore.httpoverrides": "8.0.0.0",
            "microsoft.aspnetcore.httpspolicy": "8.0.0.0",
            "microsoft.aspnetcore.identity": "8.0.0.0",
            "microsoft.aspnetcore.localization.routing": "8.0.0.0",
            "microsoft.aspnetcore.localization": "8.0.0.0",
            "microsoft.aspnetcore.metadata": "8.0.0.0",
            "microsoft.aspnetcore.mvc.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.mvc.apiexplorer": "8.0.0.0",
            "microsoft.aspnetcore.mvc.core": "8.0.0.0",
            "microsoft.aspnetcore.mvc.cors": "8.0.0.0",
            "microsoft.aspnetcore.mvc.dataannotations": "8.0.0.0",
            "microsoft.aspnetcore.mvc.formatters.json": "8.0.0.0",
            "microsoft.aspnetcore.mvc.formatters.xml": "8.0.0.0",
            "microsoft.aspnetcore.mvc.localization": "8.0.0.0",
            "microsoft.aspnetcore.mvc.razor": "8.0.0.0",
            "microsoft.aspnetcore.mvc.razorpages": "8.0.0.0",
            "microsoft.aspnetcore.mvc.taghelpers": "8.0.0.0",
            "microsoft.aspnetcore.mvc.viewfeatures": "8.0.0.0",
            "microsoft.aspnetcore.mvc": "8.0.0.0",
            "microsoft.aspnetcore.outputcaching": "8.0.0.0",
            "microsoft.aspnetcore.ratelimiting": "8.0.0.0",
            "microsoft.aspnetcore.razor.runtime": "8.0.0.0",
            "microsoft.aspnetcore.razor": "8.0.0.0",
            "microsoft.aspnetcore.requestdecompression": "8.0.0.0",
            "microsoft.aspnetcore.responsecaching.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.responsecaching": "8.0.0.0",
            "microsoft.aspnetcore.responsecompression": "8.0.0.0",
            "microsoft.aspnetcore.rewrite": "8.0.0.0",
            "microsoft.aspnetcore.routing.abstractions": "8.0.0.0",
            "microsoft.aspnetcore.routing": "8.0.0.0",
            "microsoft.aspnetcore.server.httpsys": "8.0.0.0",
            "microsoft.aspnetcore.server.iis": "8.0.0.0",
            "microsoft.aspnetcore.server.iisintegration": "8.0.0.0",
            "microsoft.aspnetcore.server.kestrel.core": "8.0.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.namedpipes": "8.0.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.quic": "8.0.0.0",
            "microsoft.aspnetcore.server.kestrel.transport.sockets": "8.0.0.0",
            "microsoft.aspnetcore.server.kestrel": "8.0.0.0",
            "microsoft.aspnetcore.session": "8.0.0.0",
            "microsoft.aspnetcore.signalr.common": "8.0.0.0",
            "microsoft.aspnetcore.signalr.core": "8.0.0.0",
            "microsoft.aspnetcore.signalr.protocols.json": "8.0.0.0",
            "microsoft.aspnetcore.signalr": "8.0.0.0",
            "microsoft.aspnetcore.staticfiles": "8.0.0.0",
            "microsoft.aspnetcore.websockets": "8.0.0.0",
            "microsoft.aspnetcore.webutilities": "8.0.0.0",
            "microsoft.aspnetcore": "8.0.0.0",
            "microsoft.extensions.caching.abstractions": "8.0.0.0",
            "microsoft.extensions.caching.memory": "8.0.0.0",
            "microsoft.extensions.configuration.abstractions": "8.0.0.0",
            "microsoft.extensions.configuration.binder": "8.0.0.0",
            "microsoft.extensions.configuration.commandline": "8.0.0.0",
            "microsoft.extensions.configuration.environmentvariables": "8.0.0.0",
            "microsoft.extensions.configuration.fileextensions": "8.0.0.0",
            "microsoft.extensions.configuration.ini": "8.0.0.0",
            "microsoft.extensions.configuration.json": "8.0.0.0",
            "microsoft.extensions.configuration.keyperfile": "8.0.0.0",
            "microsoft.extensions.configuration.usersecrets": "8.0.0.0",
            "microsoft.extensions.configuration.xml": "8.0.0.0",
            "microsoft.extensions.configuration": "8.0.0.0",
            "microsoft.extensions.dependencyinjection.abstractions": "8.0.0.0",
            "microsoft.extensions.dependencyinjection": "8.0.0.0",
            "microsoft.extensions.diagnostics.abstractions": "8.0.0.0",
            "microsoft.extensions.diagnostics.healthchecks.abstractions": "8.0.0.0",
            "microsoft.extensions.diagnostics.healthchecks": "8.0.0.0",
            "microsoft.extensions.diagnostics": "8.0.0.0",
            "microsoft.extensions.features": "8.0.0.0",
            "microsoft.extensions.fileproviders.abstractions": "8.0.0.0",
            "microsoft.extensions.fileproviders.composite": "8.0.0.0",
            "microsoft.extensions.fileproviders.embedded": "8.0.0.0",
            "microsoft.extensions.fileproviders.physical": "8.0.0.0",
            "microsoft.extensions.filesystemglobbing": "8.0.0.0",
            "microsoft.extensions.hosting.abstractions": "8.0.0.0",
            "microsoft.extensions.hosting": "8.0.0.0",
            "microsoft.extensions.http": "8.0.0.0",
            "microsoft.extensions.identity.core": "8.0.0.0",
            "microsoft.extensions.identity.stores": "8.0.0.0",
            "microsoft.extensions.localization.abstractions": "8.0.0.0",
            "microsoft.extensions.localization": "8.0.0.0",
            "microsoft.extensions.logging.abstractions": "8.0.0.0",
            "microsoft.extensions.logging.configuration": "8.0.0.0",
            "microsoft.extensions.logging.console": "8.0.0.0",
            "microsoft.extensions.logging.debug": "8.0.0.0",
            "microsoft.extensions.logging.eventlog": "8.0.0.0",
            "microsoft.extensions.logging.eventsource": "8.0.0.0",
            "microsoft.extensions.logging.tracesource": "8.0.0.0",
            "microsoft.extensions.logging": "8.0.0.0",
            "microsoft.extensions.objectpool": "8.0.0.0",
            "microsoft.extensions.options.configurationextensions": "8.0.0.0",
            "microsoft.extensions.options.dataannotations": "8.0.0.0",
            "microsoft.extensions.options": "8.0.0.0",
            "microsoft.extensions.primitives": "8.0.0.0",
            "microsoft.extensions.webencoders": "8.0.0.0",
            "microsoft.jsinterop": "8.0.0.0",
            "microsoft.net.http.headers": "8.0.0.0",
            "system.diagnostics.eventlog": "8.0.0.0",
            "system.io.pipelines": "8.0.0.0",
            "system.security.cryptography.xml": "8.0.0.0",
            "system.threading.ratelimiting": "8.0.0.0",
        },
    )
