using System.Threading.Tasks;
using Microsoft.Testing.Platform.Builder;
using Microsoft.VisualStudio.TestTools.UnitTesting;

internal static class MSTestShim {
	public static async Task<int> Main(string[] args) {
		var builder = await TestApplication.CreateBuilderAsync(args);
		builder.AddMSTest(() => new[] { typeof(MSTestShim).Assembly });
		using var app = await builder.BuildAsync();
		return await app.RunAsync();
	}
}
