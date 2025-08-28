using System;
using System.Linq;
using static Lib.Stuff;

namespace Hello {
  public static class Program {
    public static void Main() {
      Console.WriteLine( "Hello, world!" );
      Console.WriteLine( "Some numbers for you:" );
      Console.Write( "\t" );

      // silly code
      Console.WriteLine(
          Fibonacci( 0, 1 )
            .WhereNot( IsEven )
            .Take( 10 )
            .Select( x => x.ToString() )
            .Aggregate( (x, y) => x + ", " + y )
      );
    }
  }
}
