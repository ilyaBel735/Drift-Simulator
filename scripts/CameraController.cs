using Godot;

public partial class CameraController : Node3D
{
    [Export] public float MouseSensitivity = 0.3f;
    [Export] public float RotationSpeed = 6.0f;
    [Export] private float touchSensitivity = 0.3f;

    private bool rotating = false;
    private int rotationFingerIndex = -1;
    private Vector2 lastTouchPosition;
    private Vector3 targetRotation;
    private Vector3 currentRotation;

    private bool IsMobile;
    public override void _Ready()
    {
        IsMobile = OS.GetName() == "Android" || OS.GetName() == "iOS";
    }

    public override void _Input(InputEvent @event)
    {
        if (IsMobile)
        {
            if (@event is InputEventScreenTouch screenTouch)
            {
                if (screenTouch.Pressed)
                {
                    rotationFingerIndex = screenTouch.Index;
                    lastTouchPosition = screenTouch.Position;
                    rotating = true;
                }
                else if (!screenTouch.Pressed && screenTouch.Index == rotationFingerIndex)
                {
                    rotationFingerIndex = -1;
                    rotating = false;
                }
            }

            if (@event is InputEventScreenDrag screenDrag)
            {
                if (rotating && screenDrag.Index == rotationFingerIndex)
                {
                    Vector2 delta = screenDrag.Position - lastTouchPosition;
                    lastTouchPosition = screenDrag.Position;

                    targetRotation.X -= delta.X * touchSensitivity;
                    targetRotation.Y = Mathf.Clamp(
                        targetRotation.Y - delta.Y * touchSensitivity,
                        -40,
                        35
                    );
                }
            }
        }
        else
        {
            if (@event is InputEventMouseButton mouseButton)
            {
                if (mouseButton.ButtonIndex == MouseButton.Left)
                {
                    rotating = mouseButton.Pressed;
                    Input.SetMouseMode(rotating ?
                        Input.MouseModeEnum.Captured :
                        Input.MouseModeEnum.Visible);
                }
            }

            if (rotating && @event is InputEventMouseMotion mouseMotion)
            {
                targetRotation.X -= mouseMotion.Relative.X * MouseSensitivity;
                targetRotation.Y = Mathf.Clamp(
                    targetRotation.Y - mouseMotion.Relative.Y * MouseSensitivity,
                    -40,
                    35
                );
            }
        }
    }

    public override void _Process(double delta)
    {
        currentRotation = currentRotation.Lerp(
            targetRotation,
            RotationSpeed * (float)delta
        );

        RotationDegrees = new Vector3(
            currentRotation.Y,
            currentRotation.X,
            0
        );
    }
}