namespace XamlApp.Views;

public partial class MainWindow : System.Windows.Window
{
    public MainWindow()
    {
        InitializeComponent();
        Greeting.DataContext = "hello";
    }
}
