using Godot;

public partial class NewCameraController : Camera3D
{
	[Export]
	public float FollowDistance { get; set; } = 7.8f;

	[Export]
	public float FollowHeight { get; set; } = 7.8f;

	[Export]
	public float Speed { get; set; } = 20.0f;

	[Export]
	public Node3D FollowThis { get; set; }

	private Vector3 _startRotation;
	private Vector3 _startPosition;
	private float pitchVar = 14f;


	private Vector3 offsetPosition = Vector3.Zero;
	private Vector3 targetPosition = Vector3.Zero;
	private float _rotationX = 0f;

	public override void _Ready()
	{
		_startRotation = Rotation;
		_startPosition = Position;
		Input.SetMouseMode(Input.MouseModeEnum.Captured);
	}

	public override void _PhysicsProcess(double delta)
	{
		if (FollowThis == null)
			return;

		Vector3 deltaV = GlobalTransform.Origin - FollowThis.GlobalTransform.Origin;
		deltaV.Y = 0.0f;

		if (deltaV.Length() > FollowDistance)
		{
			deltaV = deltaV.Normalized() * FollowDistance;
			deltaV.Y = FollowHeight;
			GlobalPosition = FollowThis.GlobalTransform.Origin + deltaV;
			targetPosition = Position;
		}

		Vector3 offsetPositionFollowThis = new Vector3(0, 5f, 0);

		LookAt(FollowThis.GlobalTransform.Origin + offsetPositionFollowThis, Vector3.Up);
		Position = targetPosition + offsetPosition;
	}

	public override void _Input(InputEvent @event)
	{

		if (@event is InputEventKey input)
		{
			GD.Print(FollowHeight);
			if (input.Keycode == Key.Down)
			{
				if (FollowHeight < 0.6f) return;
				FollowHeight -= 0.2f;
			}
			if (input.Keycode == Key.Up)
			{
				if (FollowHeight > 15f) return;
				FollowHeight += 0.2f;
			}
		}


		if (@event is InputEventMouseMotion mouseMotion)
		{
			Vector2 delta = mouseMotion.Relative;
			_rotationX -= delta.X * 0.0005f;
			_rotationX = Mathf.Clamp(_rotationX, -180, 180);
			float rx = Mathf.Sin(_rotationX);
			float ry = Mathf.Cos(_rotationX);
			offsetPosition.X = rx;
			offsetPosition.Z = ry;
			offsetPosition *= 5f;
		}
	}
}