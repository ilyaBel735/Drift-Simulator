using Godot;

public partial class City : Node3D
{

	public override void _Ready()
	{
	}


	public override void _Process(double delta)
	{
		//Exit pressed
		if (Input.IsActionPressed("Exit"))
		{
			GetTree().Quit();
		}
	}
}
