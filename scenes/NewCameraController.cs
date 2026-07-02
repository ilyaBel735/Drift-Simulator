using Godot;

public partial class NewCameraController : Camera3D
{
	[Export]
	public float FollowDistance { get; set; } = 5.0f;

	[Export]
	public float FollowHeight { get; set; } = 1.65f;

	[Export]
	public float Speed { get; set; } = 20.0f;

	[Export]
	public Node3D FollowThis { get; set; }

	private Vector3 _startRotation;
	private Vector3 _startPosition;
	private float pitchVar = 14f;

	public override void _Ready()
	{
		_startRotation = Rotation;
		_startPosition = Position;
		FollowHeight = Position.Y;
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
		}

		LookAt(FollowThis.GlobalTransform.Origin, Vector3.Up);

		// После LookAt или вместо него
		Vector3 targetPos = FollowThis.GlobalTransform.Origin;
		Vector3 direction = (targetPos - GlobalPosition).Normalized();
		// Желаемый угол наклона в радианах (например, -45° = -0.785 радиан)
		float pitch = Mathf.DegToRad(pitchVar);
		// Поворачиваем камеру так, чтобы она смотрела в направлении direction, но с дополнительным наклоном
		Basis lookBasis = Basis.LookingAt(direction, Vector3.Up);
		// Применяем поворот вокруг локальной оси X (питч)
		lookBasis = lookBasis * new Basis(new Vector3(1, 0, 0), pitch);
		GlobalTransform = new Transform3D(lookBasis, GlobalPosition);
	}

	public override void _Input(InputEvent @event)
	{

		if (@event is InputEventKey input)
		{
			GD.Print(FollowHeight);
			if (input.Keycode == Key.Down)
			{
				if(FollowHeight < 0.6f) return;
				FollowHeight -= 0.2f;
			}
			if (input.Keycode == Key.Up)
			{
				if(FollowHeight > 5f) return;
				FollowHeight += 0.2f;
			}
		}

	}

}