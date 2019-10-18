load("@io_bazel_rules_dotnet//dotnet/private:rules/stdlib.bzl", "core_stdlib")

def all_core_stdlib(framework):
    if framework:
        context = "@io_bazel_rules_dotnet//:core_context_data_{}".format(framework)
    else:
        context = "@io_bazel_rules_dotnet//:core_context_data"

    core_stdlib(
        name = "microsoft.csharp.dll",
        deps = [
            ":netstandard.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "microsoft.visualbasic.dll",
        deps = [
            ":netstandard.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "microsoft.win32.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.interopservices.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "microsoft.win32.registry.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.accesscontrol.dll",
            ":system.security.principal.windows.dll",
            ":system.collections.dll",
            ":system.buffers.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "mscorlib.dll",
        deps = [
            ":system.private.corelib.dll",
            ":microsoft.win32.registry.dll",
            ":system.security.principal.windows.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.collections.nongeneric.dll",
            ":system.collections.concurrent.dll",
            ":system.objectmodel.dll",
            ":system.console.dll",
            ":system.diagnostics.debug.dll",
            ":system.diagnostics.stacktrace.dll",
            ":system.io.filesystem.dll",
            ":system.io.filesystem.driveinfo.dll",
            ":system.runtime.dll",
            ":system.io.isolatedstorage.dll",
            ":system.componentmodel.dll",
            ":system.threading.thread.dll",
            ":system.resources.writer.dll",
            ":system.runtime.compilerservices.visualc.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.security.accesscontrol.dll",
            ":system.io.filesystem.accesscontrol.dll",
            ":system.security.claims.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.security.cryptography.csp.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.security.principal.dll",
            ":system.threading.dll",
            ":system.threading.tasks.parallel.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "netstandard.dll",
        deps = [
            ":system.runtime.dll",
            ":system.io.memorymappedfiles.dll",
            ":system.io.pipes.dll",
            ":system.diagnostics.process.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tools.dll",
            ":system.collections.dll",
            ":system.collections.nongeneric.dll",
            ":system.collections.concurrent.dll",
            ":system.objectmodel.dll",
            ":system.collections.specialized.dll",
            ":system.componentmodel.typeconverter.dll",
            ":system.componentmodel.eventbasedasync.dll",
            ":system.componentmodel.primitives.dll",
            ":system.componentmodel.dll",
            ":microsoft.win32.primitives.dll",
            ":system.console.dll",
            ":system.data.common.dll",
            ":system.runtime.interopservices.dll",
            ":system.diagnostics.tracesource.dll",
            ":system.diagnostics.contracts.dll",
            ":system.diagnostics.debug.dll",
            ":system.diagnostics.textwritertracelistener.dll",
            ":system.diagnostics.fileversioninfo.dll",
            ":system.diagnostics.stacktrace.dll",
            ":system.diagnostics.tracing.dll",
            ":system.drawing.primitives.dll",
            ":system.linq.expressions.dll",
            ":system.io.compression.dll",
            ":system.io.compression.zipfile.dll",
            ":system.io.filesystem.dll",
            ":system.io.filesystem.driveinfo.dll",
            ":system.io.filesystem.watcher.dll",
            ":system.io.isolatedstorage.dll",
            ":system.linq.dll",
            ":system.linq.queryable.dll",
            ":system.linq.parallel.dll",
            ":system.threading.thread.dll",
            ":system.net.requests.dll",
            ":system.net.primitives.dll",
            ":system.net.httplistener.dll",
            ":system.net.servicepoint.dll",
            ":system.net.nameresolution.dll",
            ":system.net.webclient.dll",
            ":system.net.http.dll",
            ":system.net.webheadercollection.dll",
            ":system.net.webproxy.dll",
            ":system.net.mail.dll",
            ":system.net.networkinformation.dll",
            ":system.net.ping.dll",
            ":system.net.security.dll",
            ":system.net.sockets.dll",
            ":system.net.websockets.client.dll",
            ":system.net.websockets.dll",
            ":system.runtime.numerics.dll",
            ":system.threading.tasks.dll",
            ":system.reflection.primitives.dll",
            ":system.resources.resourcemanager.dll",
            ":system.resources.writer.dll",
            ":system.runtime.compilerservices.visualc.dll",
            ":system.runtime.interopservices.runtimeinformation.dll",
            ":system.runtime.serialization.primitives.dll",
            ":system.runtime.serialization.xml.dll",
            ":system.runtime.serialization.json.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.security.claims.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.security.cryptography.csp.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.security.principal.dll",
            ":system.text.encoding.extensions.dll",
            ":system.text.regularexpressions.dll",
            ":system.threading.dll",
            ":system.threading.overlapped.dll",
            ":system.threading.threadpool.dll",
            ":system.threading.tasks.parallel.dll",
            ":system.threading.timer.dll",
            ":system.transactions.local.dll",
            ":system.web.httputility.dll",
            ":system.xml.readerwriter.dll",
            ":system.xml.xdocument.dll",
            ":system.xml.xmlserializer.dll",
            ":system.xml.xpath.xdocument.dll",
            ":system.xml.xpath.dll",
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "system.appcontext.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.buffers.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.collections.concurrent.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
            ":system.collections.dll",
            ":system.diagnostics.tracing.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.collections.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.collections.immutable.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.diagnostics.tools.dll",
            ":system.linq.dll",
            ":system.threading.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.collections.nongeneric.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.collections.specialized.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.componentmodel.annotations.dll",
        deps = [
            ":netstandard.dll",
        ],
        dotnet_context_data = context,
    )

    # core_stdlib(name = "system.componentmodel.composition.dll", deps = [
    #       ":system.runtime.dll",
    #     ], dotnet_context_data = context,
    # )
    core_stdlib(
        name = "system.componentmodel.dataannotations.dll",
        deps = [
            ":system.runtime.dll",
            ":system.componentmodel.annotations.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.componentmodel.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.componentmodel.eventbasedasync.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.threading.dll",
            ":system.componentmodel.primitives.dll",
            ":system.componentmodel.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.componentmodel.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.collections.nongeneric.dll",
            ":system.componentmodel.dll",
            ":system.threading.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.componentmodel.typeconverter.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.net.security.dll",
            ":system.collections.dll",
            ":system.drawing.primitives.dll",
            ":system.componentmodel.primitives.dll",
            ":system.threading.timer.dll",
            ":system.runtime.extensions.dll",
            ":system.componentmodel.dll",
            ":system.objectmodel.dll",
            ":system.collections.specialized.dll",
            ":system.diagnostics.tracesource.dll",
            ":system.collections.nongeneric.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.linq.dll",
            ":system.resources.writer.dll",
            ":system.threading.dll",
            ":system.io.filesystem.dll",
            ":system.text.regularexpressions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.configuration.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.console.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.dll",
            ":system.text.encoding.extensions.dll",
            ":system.threading.tasks.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.core.dll",
        deps = [
            ":system.runtime.dll",
            ":system.io.memorymappedfiles.dll",
            ":system.security.cryptography.cng.dll",
            ":system.io.pipes.dll",
            ":system.collections.dll",
            ":system.linq.expressions.dll",
            ":system.linq.dll",
            ":system.linq.queryable.dll",
            ":system.linq.parallel.dll",
            ":system.runtime.interopservices.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.security.cryptography.csp.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.data.common.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.xml.readerwriter.dll",
            ":system.objectmodel.dll",
            ":system.componentmodel.typeconverter.dll",
            ":system.collections.dll",
            ":system.collections.nongeneric.dll",
            ":system.componentmodel.primitives.dll",
            ":system.diagnostics.debug.dll",
            ":system.runtime.numerics.dll",
            ":system.componentmodel.dll",
            ":system.xml.xmlserializer.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.threading.dll",
            ":system.diagnostics.tracing.dll",
            ":system.text.encoding.extensions.dll",
            ":system.collections.concurrent.dll",
            ":system.text.regularexpressions.dll",
            ":system.transactions.local.dll",
            ":system.threading.thread.dll",
            ":system.linq.expressions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.data.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.data.common.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.contracts.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.debug.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.diagnosticsource.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tracing.dll",
            ":system.collections.dll",
            ":system.threading.dll",
            ":system.diagnostics.debug.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.fileversioninfo.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.process.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.tasks.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.threadpool.dll",
            ":system.componentmodel.primitives.dll",
            ":system.threading.thread.dll",
            ":system.diagnostics.fileversioninfo.dll",
            ":system.collections.nongeneric.dll",
            ":system.collections.specialized.dll",
            ":microsoft.win32.registry.dll",
            ":system.text.encoding.extensions.dll",
            ":system.threading.dll",
            ":system.componentmodel.typeconverter.dll",
            ":microsoft.win32.primitives.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.stacktrace.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.runtime.extensions.dll",
            ":system.reflection.metadata.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.textwritertracelistener.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tracesource.dll",
            ":system.collections.nongeneric.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.tools.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.tracesource.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.threading.dll",
            ":system.collections.nongeneric.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.specialized.dll",
            ":system.runtime.extensions.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.diagnostics.tracing.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.collections.dll",
            ":system.io.compression.dll",
            ":system.net.primitives.dll",
            ":system.diagnostics.process.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.diagnostics.tools.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.concurrent.dll",
            ":system.runtime.dll",
            ":system.objectmodel.dll",
            ":system.collections.specialized.dll",
            ":system.collections.nongeneric.dll",
            ":system.componentmodel.typeconverter.dll",
            ":system.componentmodel.eventbasedasync.dll",
            ":system.componentmodel.primitives.dll",
            ":system.componentmodel.dll",
            ":microsoft.win32.primitives.dll",
            ":system.diagnostics.tracesource.dll",
            ":system.diagnostics.textwritertracelistener.dll",
            ":system.diagnostics.fileversioninfo.dll",
            ":system.private.uri.dll",
            ":system.io.filesystem.watcher.dll",
            ":system.net.requests.dll",
            ":system.net.httplistener.dll",
            ":system.net.servicepoint.dll",
            ":system.net.nameresolution.dll",
            ":system.net.webclient.dll",
            ":system.net.webheadercollection.dll",
            ":system.net.webproxy.dll",
            ":system.net.mail.dll",
            ":system.net.networkinformation.dll",
            ":system.net.ping.dll",
            ":system.net.security.dll",
            ":system.net.sockets.dll",
            ":system.net.websockets.client.dll",
            ":system.net.websockets.dll",
            ":system.runtime.interopservices.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.text.regularexpressions.dll",
            ":system.threading.dll",
            ":system.threading.thread.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.drawing.dll",
        deps = [
            ":system.runtime.dll",
            ":system.drawing.primitives.dll",
            ":system.componentmodel.typeconverter.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.drawing.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.componentmodel.primitives.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.dynamic.runtime.dll",
        deps = [
            ":system.runtime.dll",
            ":system.linq.expressions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.globalization.calendars.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.globalization.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.globalization.extensions.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.compression.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
            ":system.buffers.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.compression.filesystem.dll",
        deps = [
            ":system.runtime.dll",
            ":system.io.compression.zipfile.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.filesystem.accesscontrol.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.io.filesystem.dll",
            ":system.security.accesscontrol.dll",
            ":system.security.principal.windows.dll",
            ":system.collections.nongeneric.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.filesystem.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.overlapped.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.threading.tasks.dll",
            ":system.text.encoding.extensions.dll",
            ":system.buffers.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.filesystem.driveinfo.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.io.filesystem.dll",
            ":system.threading.tasks.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.filesystem.primitives.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.filesystem.watcher.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.overlapped.dll",
            ":system.componentmodel.primitives.dll",
            ":system.threading.tasks.dll",
            ":system.io.filesystem.dll",
            ":system.threading.dll",
            ":microsoft.win32.primitives.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.isolatedstorage.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.threading.dll",
            ":system.io.filesystem.dll",
            ":system.io.filesystem.accesscontrol.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.linq.dll",
            ":system.security.accesscontrol.dll",
            ":system.security.principal.windows.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.memorymappedfiles.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.pipes.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.overlapped.dll",
            ":system.security.principal.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.io.unmanagedmemorystream.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.linq.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.diagnostics.tools.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.linq.expressions.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.reflection.emit.ilgeneration.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tools.dll",
            ":system.reflection.emit.dll",
            ":system.objectmodel.dll",
            ":system.reflection.primitives.dll",
            ":system.reflection.emit.lightweight.dll",
            ":system.threading.dll",
            ":system.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.linq.parallel.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.linq.dll",
            ":system.diagnostics.tools.dll",
            ":system.collections.concurrent.dll",
            ":system.threading.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.tracing.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.linq.queryable.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.diagnostics.debug.dll",
            ":system.linq.expressions.dll",
            ":system.collections.dll",
            ":system.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.dll",
        deps = [
            ":system.runtime.dll",
            ":system.net.primitives.dll",
            ":system.net.webclient.dll",
            ":system.net.webheadercollection.dll",
            ":system.net.requests.dll",
            ":system.net.networkinformation.dll",
            ":system.net.sockets.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.http.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.debug.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.diagnostics.tracing.dll",
            ":system.net.primitives.dll",
            ":system.collections.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.diagnosticsource.dll",
            ":microsoft.win32.primitives.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.threading.dll",
            ":system.collections.nongeneric.dll",
            ":system.buffers.dll",
            ":system.io.compression.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.httplistener.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.threading.overlapped.dll",
            ":system.net.webheadercollection.dll",
            ":system.collections.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.net.security.dll",
            ":system.collections.specialized.dll",
            ":system.security.principal.dll",
            ":system.security.principal.windows.dll",
            ":microsoft.win32.primitives.dll",
            ":system.threading.dll",
            ":system.security.claims.dll",
            ":system.diagnostics.tracing.dll",
            ":system.net.websockets.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.timer.dll",
            ":system.net.requests.dll",
            ":system.net.nameresolution.dll",
            ":system.text.encoding.extensions.dll",
            ":system.collections.nongeneric.dll",
            ":system.security.cryptography.primitives.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.mail.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.collections.dll",
            ":system.collections.specialized.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.diagnostics.tracing.dll",
            ":system.net.sockets.dll",
            ":system.net.security.dll",
            ":system.threading.dll",
            ":system.security.principal.windows.dll",
            ":system.net.primitives.dll",
            ":microsoft.win32.primitives.dll",
            ":system.net.requests.dll",
            ":system.componentmodel.eventbasedasync.dll",
            ":system.threading.timer.dll",
            ":system.net.servicepoint.dll",
            ":system.net.networkinformation.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.nameresolution.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.diagnostics.tracing.dll",
            ":system.collections.dll",
            ":system.threading.dll",
            ":system.security.principal.windows.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.networkinformation.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.net.sockets.dll",
            ":system.diagnostics.tracing.dll",
            ":system.collections.dll",
            ":system.threading.dll",
            ":system.security.principal.windows.dll",
            ":system.threading.overlapped.dll",
            ":microsoft.win32.primitives.dll",
            ":system.threading.threadpool.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.ping.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.diagnostics.tracing.dll",
            ":system.componentmodel.primitives.dll",
            ":system.threading.dll",
            ":system.threading.threadpool.dll",
            ":system.threading.tasks.dll",
            ":system.componentmodel.eventbasedasync.dll",
            ":system.diagnostics.debug.dll",
            ":system.net.nameresolution.dll",
            ":microsoft.win32.primitives.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.collections.nongeneric.dll",
            ":system.diagnostics.tracing.dll",
            ":microsoft.win32.primitives.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.requests.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.specialized.dll",
            ":system.net.primitives.dll",
            ":system.net.webheadercollection.dll",
            ":system.threading.dll",
            ":system.net.http.dll",
            ":system.net.servicepoint.dll",
            ":system.threading.tasks.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.net.security.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.security.principal.dll",
            ":system.net.sockets.dll",
            ":system.diagnostics.tracing.dll",
            ":system.security.principal.windows.dll",
            ":system.threading.thread.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.security.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.collections.concurrent.dll",
            ":system.collections.dll",
            ":system.diagnostics.tracing.dll",
            ":system.net.primitives.dll",
            ":system.collections.nongeneric.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
            ":system.security.cryptography.encoding.dll",
            ":microsoft.win32.primitives.dll",
            ":system.security.principal.dll",
            ":system.security.principal.windows.dll",
            ":system.threading.threadpool.dll",
            ":system.security.claims.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.servicepoint.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.collections.concurrent.dll",
            ":system.net.security.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.sockets.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.threading.overlapped.dll",
            ":system.diagnostics.tracing.dll",
            ":system.collections.dll",
            ":system.threading.dll",
            ":system.security.principal.windows.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.buffers.dll",
            ":system.net.nameresolution.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.webclient.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.componentmodel.primitives.dll",
            ":system.componentmodel.eventbasedasync.dll",
            ":system.net.primitives.dll",
            ":system.net.webheadercollection.dll",
            ":system.collections.specialized.dll",
            ":system.net.requests.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.webheadercollection.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.specialized.dll",
            ":system.diagnostics.tracing.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.webproxy.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.extensions.dll",
            ":system.net.primitives.dll",
            ":system.text.regularexpressions.dll",
            ":system.net.nameresolution.dll",
            ":system.net.networkinformation.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.websockets.client.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tracing.dll",
            ":microsoft.win32.primitives.dll",
            ":system.net.websockets.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.net.webheadercollection.dll",
            ":system.net.primitives.dll",
            ":system.security.cryptography.x509certificates.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.net.websockets.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.collections.specialized.dll",
            ":system.net.primitives.dll",
            ":system.security.principal.dll",
            ":microsoft.win32.primitives.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.numerics.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.numerics.dll",
            ":system.numerics.vectors.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.numerics.vectors.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.objectmodel.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.private.datacontractserialization.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.xml.readerwriter.dll",
            ":system.text.encoding.extensions.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.reflection.emit.lightweight.dll",
            ":system.reflection.emit.ilgeneration.dll",
            ":system.reflection.primitives.dll",
            ":system.runtime.serialization.primitives.dll",
            ":system.xml.xmlserializer.dll",
            ":system.collections.nongeneric.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.threading.dll",
            ":system.linq.dll",
            ":system.text.regularexpressions.dll",
            ":system.xml.xdocument.dll",
            ":system.collections.specialized.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.private.uri.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.private.xml.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.tracesource.dll",
            ":system.text.regularexpressions.dll",
            ":system.net.primitives.dll",
            ":system.net.requests.dll",
            ":system.text.encoding.extensions.dll",
            ":system.threading.tasks.extensions.dll",
            ":system.reflection.emit.dll",
            ":system.reflection.emit.ilgeneration.dll",
            ":system.collections.nongeneric.dll",
            ":system.reflection.primitives.dll",
            ":system.collections.specialized.dll",
            ":system.threading.dll",
            ":system.diagnostics.tools.dll",
            ":system.reflection.emit.lightweight.dll",
            ":system.objectmodel.dll",
            ":system.linq.dll",
            ":system.io.filesystem.dll",
            ":system.console.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.private.xml.linq.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.private.xml.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.runtime.extensions.dll",
            ":system.diagnostics.tools.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
            ":system.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.dispatchproxy.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.collections.dll",
            ":system.reflection.emit.dll",
            ":system.reflection.emit.ilgeneration.dll",
            ":system.reflection.primitives.dll",
            ":system.threading.dll",
            ":system.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.emit.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.emit.ilgeneration.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.emit.lightweight.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.extensions.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.metadata.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.immutable.dll",
            ":system.diagnostics.debug.dll",
            ":system.collections.dll",
            ":system.io.compression.dll",
            ":system.io.memorymappedfiles.dll",
            ":system.threading.dll",
            ":system.text.encoding.extensions.dll",
            ":system.buffers.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.primitives.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.reflection.typeextensions.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.resources.reader.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.resources.resourcemanager.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.resources.writer.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.compilerservices.visualc.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.private.uri.dll",
            ":system.runtime.loader.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.extensions.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.security.principal.dll",
            ":system.private.uri.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.handles.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.interopservices.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.interopservices.runtimeinformation.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.interopservices.windowsruntime.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.loader.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.numerics.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.serialization.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.serialization.primitives.dll",
            ":system.runtime.serialization.xml.dll",
            ":system.runtime.serialization.json.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.serialization.formatters.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.collections.nongeneric.dll",
            ":system.collections.concurrent.dll",
            ":system.collections.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.dll",
            ":system.text.encoding.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.serialization.json.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.datacontractserialization.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.serialization.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.runtime.serialization.xml.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.datacontractserialization.dll",
            ":system.runtime.serialization.primitives.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.accesscontrol.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.principal.windows.dll",
            ":system.collections.dll",
            ":system.threading.dll",
            ":system.threading.thread.dll",
            ":system.collections.nongeneric.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.claims.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.security.principal.dll",
            ":system.collections.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.algorithms.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.cng.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.security.cryptography.algorithms.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.csp.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.threading.dll",
            ":system.text.encoding.extensions.dll",
            ":system.threading.thread.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.encoding.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.collections.concurrent.dll",
            ":system.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.openssl.dll",
        deps = [
            ":netstandard.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.primitives.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.threading.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.debug.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.cryptography.x509certificates.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.security.cryptography.cng.dll",
            ":system.security.cryptography.encoding.dll",
            ":system.runtime.numerics.dll",
            ":system.collections.dll",
            ":system.security.cryptography.primitives.dll",
            ":system.security.cryptography.algorithms.dll",
            ":system.net.primitives.dll",
            ":system.collections.nongeneric.dll",
            ":system.security.cryptography.csp.dll",
            ":system.threading.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.principal.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.principal.windows.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.security.claims.dll",
            ":system.security.principal.dll",
            ":system.threading.dll",
            ":system.diagnostics.debug.dll",
            ":microsoft.win32.primitives.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.security.securestring.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.interopservices.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.servicemodel.web.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.serialization.json.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.serviceprocess.dll",
        deps = [
            ":system.runtime.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.text.encoding.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.text.encoding.extensions.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.text.regularexpressions.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.overlapped.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.tasks.dataflow.dll",
        deps = [
            ":netstandard.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.tasks.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.tasks.extensions.dll",
        deps = [
            ":system.runtime.dll",
            ":system.threading.tasks.dll",
            ":system.collections.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.tasks.parallel.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.concurrent.dll",
            ":system.threading.tasks.dll",
            ":system.diagnostics.tracing.dll",
            ":system.diagnostics.debug.dll",
            ":system.threading.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.thread.dll",
        deps = [
            ":system.private.corelib.dll",
            ":system.security.principal.dll",
            ":system.runtime.extensions.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.threadpool.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.threading.timer.dll",
        deps = [
            ":system.private.corelib.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.transactions.dll",
        deps = [
            ":system.runtime.dll",
            ":system.transactions.local.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.transactions.local.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
            ":system.runtime.interopservices.dll",
            ":system.runtime.extensions.dll",
            ":system.threading.dll",
            ":system.runtime.serialization.formatters.dll",
            ":system.threading.timer.dll",
            ":system.threading.thread.dll",
            ":system.threading.threadpool.dll",
            ":system.diagnostics.tracing.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.valuetuple.dll",
        deps = [
            ":system.runtime.dll",
            ":system.resources.resourcemanager.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.web.dll",
        deps = [
            ":system.runtime.dll",
            ":system.web.httputility.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.web.httputility.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.extensions.dll",
            ":system.collections.specialized.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.windows.dll",
        deps = [
            ":system.runtime.dll",
            ":system.objectmodel.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.dll",
        deps = [
            ":system.runtime.dll",
            ":system.xml.readerwriter.dll",
            ":system.xml.xmlserializer.dll",
            ":system.xml.xpath.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.linq.dll",
        deps = [
            ":system.runtime.dll",
            ":system.xml.xdocument.dll",
            ":system.xml.xpath.xdocument.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.readerwriter.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.xml.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.serialization.dll",
        deps = [
            ":system.runtime.dll",
            ":system.xml.readerwriter.dll",
            ":system.xml.xmlserializer.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.xdocument.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.xml.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.xmldocument.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.xml.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.xmlserializer.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.xml.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.xpath.dll",
        deps = [
            ":system.runtime.dll",
            ":system.private.xml.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "system.xml.xpath.xdocument.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.extensions.dll",
            ":system.private.xml.dll",
            ":system.private.xml.linq.dll",
        ],
        dotnet_context_data = context,
    )
    core_stdlib(
        name = "windowsbase.dll",
        deps = [
            ":system.runtime.dll",
            ":system.objectmodel.dll",
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "system.security.cryptography.protecteddata.dll",
        deps = [
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "microsoft.dotnet.internalabstractions.dll",
        deps = [
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "microsoft.dotnet.platformabstractions.dll",
        deps = [
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "microsoft.extensions.dependencymodel.dll",
        deps = [
        ],
        dotnet_context_data = context,
    )

    if framework:
        core_stdlib(
            name = "system.io.compression.zipfile.dll",
            dll = "system.io.compression.zipfile.dll",
            deps = [
                ":system.runtime.dll",
                ":system.resources.resourcemanager.dll",
                ":system.runtime.extensions.dll",
                ":system.io.compression.dll",
                ":system.io.filesystem.dll",
                ":system.buffers.dll",
            ],
            data = select({
                "@bazel_tools//src/conditions:windows": ["@core_sdk_{}//:shared/clrcompression.dll".format(framework)],
                "//conditions:default": [],
            }),
            dotnet_context_data = context,
        )
    else:
        core_stdlib(
            name = "system.io.compression.zipfile.dll",
            dll = "system.io.compression.zipfile.dll",
            deps = [
                ":system.runtime.dll",
                ":system.resources.resourcemanager.dll",
                ":system.runtime.extensions.dll",
                ":system.io.compression.dll",
                ":system.io.filesystem.dll",
                ":system.buffers.dll",
            ],
            data = select({
                "@bazel_tools//src/conditions:windows": ["@core_sdk//:shared/clrcompression.dll"],
                "//conditions:default": [],
            }),
            dotnet_context_data = context,
        )

    native.alias(
        name = "netstandard.library.dll",
        actual = ":netstandard.dll",
    )

def all_core_stdlib215(framework):
    if framework:
        context = "@io_bazel_rules_dotnet//:core_context_data_{}".format(framework)
    else:
        context = "@io_bazel_rules_dotnet//:core_context_data"

    core_stdlib(
        name = "system.memory.dll",
        dll = "system.memory.dll",
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "system.private.corelib.dll",
        dll = "system.private.corelib.dll",
        dotnet_context_data = context,
        deps = ["system.memory.dll"],
    )

def all_core_stdlibbelow3(framework):
    if framework:
        context = "@io_bazel_rules_dotnet//:core_context_data_{}".format(framework)
    else:
        context = "@io_bazel_rules_dotnet//:core_context_data"

    core_stdlib(
        name = "system.xml.xpath.xmldocument.dll",
        deps = [
        ],
        dotnet_context_data = context,
    )

    core_stdlib(
        name = "sos.netcore.dll",
        deps = [
            ":system.runtime.dll",
            ":system.runtime.interopservices.dll",
            ":system.reflection.metadata.dll",
            ":system.collections.dll",
            ":system.io.dll",
            ":system.collections.immutable.dll",
            ":system.diagnostics.debug.dll",
            ":system.runtime.extensions.dll",
            ":system.io.filesystem.dll",
        ],
        dotnet_context_data = context,
    )
