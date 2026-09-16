namespace D {
  public static class D {
    public static string DFramework()
    {
      #if NETSTANDARD2_1
      return "netstandard2.1";
      #elif NET8_0
      return "net8.0";
      #endif
    }

  }
}
