using System;
using System.Collections.Generic;
using System.Linq;

namespace Lib {
  public static class Stuff {
    public static IEnumerable<T> WhereNot<T>( this IEnumerable<T> @this, Func<T, bool> fn )
      => @this.Where( t => !fn( t ) );

    public static IEnumerable<int> Fibonacci( int x0, int x1 ) {
      while (true) {
        yield return x0;
        var next = x0 + x1;
        x0 = x1;
        x1 = next;
      }
    }

    public static bool IsEven( int x ) => x%2 == 0;
    
    internal static int NonPublicMethod() => 42;
  }
}
