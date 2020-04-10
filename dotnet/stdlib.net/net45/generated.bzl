load("@io_bazel_rules_dotnet//dotnet/private:rules/stdlib.bzl", "net_stdlib")

def define_stdlib(context_data):
    net_stdlib(
        name = "accessibility.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Accessibility.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Accessibility.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "custommarshalers.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/CustomMarshalers.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/CustomMarshalers.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "isymwrapper.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/ISymWrapper.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/ISymWrapper.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.activities.build.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Activities.Build.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Activities.Build.dll",
        deps = [
            ":mscorlib.dll",
            ":xamlbuildtask.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":system.xaml.dll",
            ":system.dll",
            ":system.activities.dll",
            ":microsoft.build.framework.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.conversion.v4.0.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Conversion.v4.0.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Conversion.v4.0.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.build.dll",
            ":system.dll",
            ":microsoft.build.engine.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.build.framework.dll",
            ":system.dll",
            ":system.core.dll",
            ":microsoft.build.engine.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.engine.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Engine.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Engine.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.build.framework.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.framework.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Framework.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Framework.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.tasks.v4.0.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Tasks.v4.0.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Tasks.v4.0.dll",
        deps = [
            ":system.security.dll",
            ":mscorlib.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":microsoft.build.framework.dll",
            ":system.dll",
            ":system.core.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.build.utilities.v4.0.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Utilities.v4.0.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.Build.Utilities.v4.0.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.build.framework.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.csharp.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.CSharp.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.CSharp.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.jscript.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.JScript.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.JScript.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.visualbasic.compatibility.data.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.Compatibility.Data.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.Compatibility.Data.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.visualbasic.dll",
            ":system.drawing.dll",
            ":system.dll",
            ":microsoft.visualbasic.compatibility.dll",
            ":system.security.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.visualbasic.compatibility.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.Compatibility.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.Compatibility.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.visualbasic.dll",
            ":system.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.visualbasic.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualBasic.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.deployment.dll",
            ":system.management.dll",
            ":system.core.dll",
            ":system.xml.linq.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.visualc.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualC.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualC.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "microsoft.visualc.stlclr.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualC.STLCLR.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Microsoft.VisualC.STLCLR.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "mscorlib.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/mscorlib.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/mscorlib.dll",
        deps = [
        ]
    )
    net_stdlib(
        name = "presentationbuildtasks.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationBuildTasks.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationBuildTasks.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":microsoft.build.framework.dll",
        ]
    )
    net_stdlib(
        name = "presentationcore.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationCore.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationCore.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":windowsbase.dll",
            ":uiautomationprovider.dll",
            ":system.xaml.dll",
            ":uiautomationtypes.dll",
            ":system.windows.input.manipulations.dll",
            ":system.deployment.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.aero.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Aero.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Aero.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.aero2.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Aero2.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Aero2.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.aerolite.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.AeroLite.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.AeroLite.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.classic.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Classic.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Classic.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
            ":windowsbase.dll",
            ":uiautomationprovider.dll",
            ":system.core.dll",
            ":system.deployment.dll",
            ":reachframework.dll",
            ":uiautomationtypes.dll",
            ":accessibility.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.luna.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Luna.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Luna.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "presentationframework.royale.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Royale.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/PresentationFramework.Royale.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "reachframework.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/ReachFramework.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/ReachFramework.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":presentationcore.dll",
            ":windowsbase.dll",
            ":system.drawing.dll",
            ":system.security.dll",
        ]
    )
    net_stdlib(
        name = "sysglobl.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/sysglobl.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/sysglobl.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.activities.core.presentation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.Core.Presentation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.Core.Presentation.dll",
        deps = [
            ":system.activities.presentation.dll",
            ":system.xaml.dll",
            ":mscorlib.dll",
            ":presentationcore.dll",
            ":system.dll",
            ":windowsbase.dll",
            ":system.activities.dll",
            ":system.core.dll",
            ":system.servicemodel.activities.dll",
            ":system.windows.presentation.dll",
            ":system.xml.linq.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.activities.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.xml.linq.dll",
            ":system.xaml.dll",
            ":system.core.dll",
            ":system.runtime.serialization.dll",
            ":microsoft.visualbasic.dll",
        ]
    )
    net_stdlib(
        name = "system.activities.durableinstancing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.DurableInstancing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.DurableInstancing.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.xml.linq.dll",
            ":system.core.dll",
            ":system.activities.dll",
            ":system.runtime.serialization.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.activities.presentation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.Presentation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Activities.Presentation.dll",
        deps = [
            ":mscorlib.dll",
            ":presentationcore.dll",
            ":system.xaml.dll",
            ":system.dll",
            ":uiautomationprovider.dll",
            ":windowsbase.dll",
            ":system.activities.dll",
            ":system.core.dll",
            ":system.componentmodel.composition.dll",
            ":system.servicemodel.activities.dll",
            ":uiautomationtypes.dll",
            ":system.drawing.dll",
            ":system.xml.linq.dll",
            ":windowsformsintegration.dll",
            ":reachframework.dll",
        ]
    )
    net_stdlib(
        name = "system.addin.contract.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.AddIn.Contract.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.AddIn.Contract.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.addin.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.AddIn.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.AddIn.dll",
        deps = [
            ":mscorlib.dll",
            ":system.addin.contract.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.composition.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.Composition.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.Composition.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.composition.registration.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.Composition.Registration.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.Composition.Registration.dll",
        deps = [
            ":mscorlib.dll",
            ":system.reflection.context.dll",
            ":system.core.dll",
            ":system.componentmodel.composition.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.dataannotations.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.DataAnnotations.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ComponentModel.DataAnnotations.dll",
        deps = [
            ":system.dll",
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.configuration.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Configuration.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Configuration.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.security.dll",
        ]
    )
    net_stdlib(
        name = "system.configuration.install.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Configuration.Install.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Configuration.Install.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.core.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Core.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Core.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.security.dll",
            ":system.numerics.dll",
        ]
    )
    net_stdlib(
        name = "system.data.datasetextensions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.DataSetExtensions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.DataSetExtensions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.data.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.numerics.dll",
            ":system.enterpriseservices.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.data.entity.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Entity.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Entity.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.data.entity.dll",
            ":system.dll",
            ":system.core.dll",
            ":system.data.datasetextensions.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.data.entity.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Entity.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Entity.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
            ":system.componentmodel.dataannotations.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.data.linq.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Linq.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Linq.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
            ":system.xml.linq.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.data.oracleclient.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.OracleClient.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.OracleClient.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.enterpriseservices.dll",
        ]
    )
    net_stdlib(
        name = "system.data.services.client.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.Client.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.Client.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.data.services.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.data.entity.dll",
            ":system.dll",
            ":system.data.services.client.dll",
            ":system.xml.linq.dll",
            ":system.core.dll",
            ":system.web.extensions.dll",
        ]
    )
    net_stdlib(
        name = "system.data.services.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.Services.dll",
        deps = [
            ":mscorlib.dll",
            ":system.servicemodel.web.dll",
            ":system.servicemodel.activation.dll",
            ":system.core.dll",
            ":system.dll",
            ":system.data.services.client.dll",
            ":system.runtime.serialization.dll",
            ":system.data.entity.dll",
            ":system.xml.linq.dll",
            ":system.data.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.data.sqlxml.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.SqlXml.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Data.SqlXml.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.deployment.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Deployment.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Deployment.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.security.dll",
            ":system.drawing.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
            ":system.drawing.design.dll",
            ":system.data.oracleclient.dll",
            ":system.runtime.serialization.formatters.soap.dll",
            ":accessibility.dll",
            ":system.web.regularexpressions.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.device.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Device.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Device.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.directoryservices.accountmanagement.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.AccountManagement.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.AccountManagement.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.directoryservices.protocols.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.directoryservices.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.directoryservices.protocols.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.Protocols.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.DirectoryServices.Protocols.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.drawing.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Drawing.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Drawing.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.drawing.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.drawing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Drawing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Drawing.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.enterpriseservices.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.EnterpriseServices.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.EnterpriseServices.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.identitymodel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
            ":system.dll",
            ":system.web.applicationservices.dll",
            ":system.core.dll",
            ":system.security.dll",
        ]
    )
    net_stdlib(
        name = "system.identitymodel.selectors.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.Selectors.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.Selectors.dll",
        deps = [
            ":mscorlib.dll",
            ":system.identitymodel.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.identitymodel.services.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.Services.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IdentityModel.Services.dll",
        deps = [
            ":mscorlib.dll",
            ":system.identitymodel.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
            ":system.web.applicationservices.dll",
        ]
    )
    net_stdlib(
        name = "system.io.compression.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Compression.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Compression.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.io.compression.filesystem.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Compression.FileSystem.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Compression.FileSystem.dll",
        deps = [
            ":mscorlib.dll",
            ":system.io.compression.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.io.log.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Log.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.IO.Log.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.management.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Management.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Management.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.configuration.install.dll",
            ":microsoft.jscript.dll",
        ]
    )
    net_stdlib(
        name = "system.management.instrumentation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Management.Instrumentation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Management.Instrumentation.dll",
        deps = [
            ":mscorlib.dll",
            ":system.configuration.install.dll",
            ":system.dll",
            ":system.management.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.messaging.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Messaging.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Messaging.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.configuration.install.dll",
            ":system.drawing.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.net.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.net.http.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.Http.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.Http.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.net.http.webrequest.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.Http.WebRequest.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Net.Http.WebRequest.dll",
        deps = [
            ":mscorlib.dll",
            ":system.net.http.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.numerics.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Numerics.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Numerics.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.printing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Printing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Printing.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
            ":system.xaml.dll",
            ":windowsbase.dll",
            ":reachframework.dll",
            ":presentationcore.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.context.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Reflection.Context.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Reflection.Context.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.caching.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Caching.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Caching.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.durableinstancing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.DurableInstancing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.DurableInstancing.dll",
        deps = [
            ":mscorlib.dll",
            ":system.xml.linq.dll",
            ":system.core.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.remoting.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Remoting.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Remoting.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.runtime.serialization.formatters.soap.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.serialization.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Serialization.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Serialization.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.serialization.formatters.soap.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Serialization.Formatters.Soap.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Runtime.Serialization.Formatters.Soap.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.security.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Security.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Security.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.activation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Activation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Activation.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
            ":system.net.http.dll",
            ":system.web.regularexpressions.dll",
            ":system.servicemodel.activities.dll",
            ":system.xml.linq.dll",
            ":system.activities.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.activities.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Activities.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Activities.dll",
        deps = [
            ":mscorlib.dll",
            ":system.activities.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.dll",
            ":system.xaml.dll",
            ":system.xml.linq.dll",
            ":system.core.dll",
            ":system.runtime.serialization.dll",
            ":system.activities.durableinstancing.dll",
            ":system.identitymodel.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.channels.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Channels.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Channels.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
            ":system.net.http.dll",
            ":system.dll",
            ":system.web.services.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.discovery.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Discovery.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Discovery.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
            ":system.servicemodel.channels.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.runtime.serialization.dll",
            ":system.dll",
            ":system.net.http.dll",
            ":system.xaml.dll",
            ":system.identitymodel.dll",
            ":system.enterpriseservices.dll",
            ":system.web.services.dll",
            ":system.web.applicationservices.dll",
            ":system.core.dll",
            ":system.serviceprocess.dll",
            ":system.xml.linq.dll",
            ":system.messaging.dll",
            ":system.identitymodel.selectors.dll",
            ":system.directoryservices.dll",
            ":system.servicemodel.activation.dll",
            ":system.security.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.routing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Routing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Routing.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.durableinstancing.dll",
            ":system.dll",
            ":system.runtime.serialization.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.web.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Web.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceModel.Web.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.servicemodel.activation.dll",
            ":system.web.extensions.dll",
            ":system.runtime.serialization.dll",
            ":system.xml.linq.dll",
            ":system.servicemodel.channels.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.serviceprocess.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceProcess.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.ServiceProcess.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.configuration.install.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "system.speech.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Speech.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Speech.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.transactions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Transactions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Transactions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.enterpriseservices.dll",
        ]
    )
    net_stdlib(
        name = "system.web.abstractions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Abstractions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Abstractions.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.web.applicationservices.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.ApplicationServices.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.ApplicationServices.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.web.datavisualization.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DataVisualization.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DataVisualization.Design.dll",
        deps = [
            ":system.drawing.dll",
            ":mscorlib.dll",
            ":system.web.datavisualization.dll",
            ":system.dll",
            ":system.drawing.design.dll",
        ]
    )
    net_stdlib(
        name = "system.web.datavisualization.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DataVisualization.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DataVisualization.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "system.web.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":microsoft.build.framework.dll",
            ":system.componentmodel.dataannotations.dll",
            ":system.core.dll",
            ":system.runtime.caching.dll",
            ":system.web.applicationservices.dll",
            ":system.drawing.dll",
            ":system.web.services.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":system.security.dll",
            ":system.directoryservices.dll",
            ":system.directoryservices.protocols.dll",
            ":system.enterpriseservices.dll",
            ":microsoft.build.tasks.v4.0.dll",
            ":system.serviceprocess.dll",
            ":system.web.regularexpressions.dll",
        ]
    )
    net_stdlib(
        name = "system.web.dynamicdata.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DynamicData.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DynamicData.Design.dll",
        deps = [
            ":system.dll",
            ":mscorlib.dll",
            ":system.web.dynamicdata.dll",
            ":system.core.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "system.web.dynamicdata.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DynamicData.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.DynamicData.dll",
        deps = [
            ":mscorlib.dll",
            ":system.web.extensions.dll",
            ":system.dll",
            ":system.core.dll",
            ":system.componentmodel.dataannotations.dll",
            ":system.data.linq.dll",
            ":system.data.entity.dll",
            ":system.drawing.dll",
            ":system.web.entity.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.web.entity.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Entity.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Entity.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
            ":system.web.entity.dll",
            ":system.data.entity.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.web.entity.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Entity.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Entity.dll",
        deps = [
            ":mscorlib.dll",
            ":system.web.extensions.dll",
            ":system.dll",
            ":system.data.entity.dll",
            ":system.core.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "system.web.extensions.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Extensions.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Extensions.Design.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.web.extensions.dll",
            ":system.drawing.dll",
            ":system.data.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.web.extensions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Extensions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Extensions.dll",
        deps = [
            ":system.servicemodel.activation.dll",
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
            ":system.web.applicationservices.dll",
            ":system.dll",
            ":system.web.services.dll",
            ":system.core.dll",
            ":system.data.linq.dll",
            ":system.drawing.dll",
            ":system.data.services.client.dll",
            ":system.data.entity.dll",
        ]
    )
    net_stdlib(
        name = "system.web.mobile.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Mobile.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Mobile.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
            ":system.web.regularexpressions.dll",
        ]
    )
    net_stdlib(
        name = "system.web.regularexpressions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.RegularExpressions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.RegularExpressions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.web.routing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Routing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Routing.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.web.services.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Services.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Web.Services.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.enterpriseservices.dll",
            ":system.directoryservices.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.controls.ribbon.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Controls.Ribbon.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Controls.Ribbon.dll",
        deps = [
            ":mscorlib.dll",
            ":uiautomationprovider.dll",
            ":presentationcore.dll",
            ":windowsbase.dll",
            ":system.dll",
            ":uiautomationtypes.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.forms.datavisualization.design.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.DataVisualization.Design.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.DataVisualization.Design.dll",
        deps = [
            ":system.drawing.dll",
            ":mscorlib.dll",
            ":system.windows.forms.datavisualization.dll",
            ":system.dll",
            ":system.drawing.design.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.forms.datavisualization.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.DataVisualization.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.DataVisualization.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.drawing.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.forms.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Forms.dll",
        deps = [
            ":mscorlib.dll",
            ":system.drawing.dll",
            ":system.security.dll",
            ":system.dll",
            ":accessibility.dll",
            ":system.deployment.dll",
            ":system.core.dll",
            ":system.runtime.serialization.formatters.soap.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.input.manipulations.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Input.Manipulations.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Input.Manipulations.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.windows.presentation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Presentation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Windows.Presentation.dll",
        deps = [
            ":system.addin.dll",
            ":mscorlib.dll",
            ":system.addin.contract.dll",
            ":windowsbase.dll",
            ":presentationcore.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.workflow.activities.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.Activities.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.Activities.dll",
        deps = [
            ":system.dll",
            ":mscorlib.dll",
            ":system.workflow.componentmodel.dll",
            ":system.drawing.dll",
            ":system.web.services.dll",
            ":system.workflow.runtime.dll",
            ":system.directoryservices.dll",
            ":system.web.applicationservices.dll",
        ]
    )
    net_stdlib(
        name = "system.workflow.componentmodel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.ComponentModel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.ComponentModel.dll",
        deps = [
            ":system.dll",
            ":mscorlib.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":microsoft.build.framework.dll",
            ":microsoft.build.tasks.v4.0.dll",
            ":system.drawing.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.workflow.runtime.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.Runtime.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Workflow.Runtime.dll",
        deps = [
            ":mscorlib.dll",
            ":system.workflow.componentmodel.dll",
            ":system.activities.dll",
            ":system.dll",
            ":system.messaging.dll",
            ":system.core.dll",
            ":system.xml.linq.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.workflowservices.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.WorkflowServices.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.WorkflowServices.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.workflow.componentmodel.dll",
            ":system.workflow.runtime.dll",
            ":system.identitymodel.dll",
            ":system.drawing.dll",
            ":system.servicemodel.activities.dll",
            ":system.runtime.serialization.dll",
            ":system.messaging.dll",
            ":system.activities.dll",
            ":system.servicemodel.activation.dll",
        ]
    )
    net_stdlib(
        name = "system.xaml.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xaml.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xaml.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.dll",
        deps = [
            ":mscorlib.dll",
            ":system.data.sqlxml.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.linq.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.Linq.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.Linq.dll",
        deps = [
            ":system.dll",
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.serialization.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.Serialization.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/System.Xml.Serialization.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "uiautomationclient.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationClient.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationClient.dll",
        deps = [
            ":mscorlib.dll",
            ":uiautomationprovider.dll",
            ":uiautomationtypes.dll",
            ":accessibility.dll",
            ":windowsbase.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "uiautomationclientsideproviders.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationClientsideProviders.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationClientsideProviders.dll",
        deps = [
            ":mscorlib.dll",
            ":uiautomationprovider.dll",
            ":uiautomationclient.dll",
            ":accessibility.dll",
            ":windowsbase.dll",
            ":uiautomationtypes.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "uiautomationprovider.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationProvider.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationProvider.dll",
        deps = [
            ":mscorlib.dll",
            ":uiautomationtypes.dll",
            ":windowsbase.dll",
        ]
    )
    net_stdlib(
        name = "uiautomationtypes.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationTypes.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/UIAutomationTypes.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "windowsbase.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/WindowsBase.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/WindowsBase.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.security.dll",
            ":system.xaml.dll",
            ":accessibility.dll",
        ]
    )
    net_stdlib(
        name = "windowsformsintegration.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/WindowsFormsIntegration.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/WindowsFormsIntegration.dll",
        deps = [
            ":mscorlib.dll",
            ":windowsbase.dll",
            ":presentationcore.dll",
            ":uiautomationprovider.dll",
            ":system.drawing.dll",
            ":system.dll",
            ":system.xaml.dll",
        ]
    )
    net_stdlib(
        name = "xamlbuildtask.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/XamlBuildTask.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/XamlBuildTask.dll",
        deps = [
            ":mscorlib.dll",
            ":microsoft.build.utilities.v4.0.dll",
            ":system.xaml.dll",
            ":microsoft.build.framework.dll",
            ":system.dll",
            ":system.xml.linq.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.collections.concurrent.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Collections.Concurrent.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Collections.Concurrent.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.collections.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Collections.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Collections.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.annotations.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.Annotations.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.Annotations.dll",
        deps = [
            ":mscorlib.dll",
            ":system.componentmodel.dataannotations.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.componentmodel.eventbasedasync.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.EventBasedAsync.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ComponentModel.EventBasedAsync.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.diagnostics.contracts.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Contracts.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Contracts.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.diagnostics.debug.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Debug.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Debug.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.diagnostics.tools.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Tools.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Tools.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.diagnostics.tracing.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Tracing.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Diagnostics.Tracing.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.dynamic.runtime.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Dynamic.Runtime.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Dynamic.Runtime.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.globalization.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Globalization.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Globalization.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.io.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.IO.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.IO.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.linq.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.linq.expressions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Expressions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Expressions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.linq.parallel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Parallel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Parallel.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.linq.queryable.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Queryable.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Linq.Queryable.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.net.networkinformation.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.NetworkInformation.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.NetworkInformation.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.net.primitives.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.Primitives.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.Primitives.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.net.requests.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.Requests.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Net.Requests.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.objectmodel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ObjectModel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ObjectModel.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.emit.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.emit.ilgeneration.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.ILGeneration.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.ILGeneration.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.emit.lightweight.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.Lightweight.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Emit.Lightweight.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.extensions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Extensions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Extensions.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.reflection.primitives.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Primitives.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Reflection.Primitives.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.resources.resourcemanager.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Resources.ResourceManager.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Resources.ResourceManager.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
            ":system.componentmodel.composition.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.extensions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Extensions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Extensions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.interopservices.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.InteropServices.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.InteropServices.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.interopservices.windowsruntime.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.InteropServices.WindowsRuntime.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.InteropServices.WindowsRuntime.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.numerics.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Numerics.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Numerics.dll",
        deps = [
            ":mscorlib.dll",
            ":system.numerics.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.serialization.json.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Json.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Json.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.serialization.primitives.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Primitives.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Primitives.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.runtime.serialization.xml.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Xml.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Runtime.Serialization.Xml.dll",
        deps = [
            ":mscorlib.dll",
            ":system.runtime.serialization.dll",
        ]
    )
    net_stdlib(
        name = "system.security.principal.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Security.Principal.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Security.Principal.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.duplex.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Duplex.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Duplex.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.http.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Http.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Http.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.nettcp.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.NetTcp.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.NetTcp.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.primitives.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Primitives.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Primitives.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.servicemodel.security.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Security.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.ServiceModel.Security.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.text.encoding.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.Encoding.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.Encoding.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.text.encoding.extensions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.Encoding.Extensions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.Encoding.Extensions.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.text.regularexpressions.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.RegularExpressions.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Text.RegularExpressions.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
        ]
    )
    net_stdlib(
        name = "system.threading.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.dll",
        deps = [
            ":mscorlib.dll",
            ":system.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.threading.tasks.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.Tasks.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.Tasks.dll",
        deps = [
            ":mscorlib.dll",
            ":system.core.dll",
        ]
    )
    net_stdlib(
        name = "system.threading.tasks.parallel.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.Tasks.Parallel.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Threading.Tasks.Parallel.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.readerwriter.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.ReaderWriter.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.ReaderWriter.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.xdocument.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.XDocument.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.XDocument.dll",
        deps = [
            ":mscorlib.dll",
            ":system.xml.linq.dll",
        ]
    )
    net_stdlib(
        name = "system.xml.xmlserializer.dll",
        dotnet_context_data = context_data,
        ref = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.XmlSerializer.dll",
        stdlib_path = "@Microsoft.NETFramework.ReferenceAssemblies.net45.1.0.0//:build/.NETFramework/v4.5/Facades/System.Xml.XmlSerializer.dll",
        deps = [
            ":mscorlib.dll",
        ]
    )
