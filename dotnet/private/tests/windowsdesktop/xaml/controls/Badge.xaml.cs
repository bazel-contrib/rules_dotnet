namespace XamlControls;

public partial class Badge : System.Windows.Controls.UserControl
{
    public const string DefaultText = "badge";

    public Badge()
    {
        InitializeComponent();
    }

    public string Text => Label.Text;
}
