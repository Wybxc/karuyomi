package android.graphics;

public class RectF {
  public float left, top, right, bottom;

  public RectF() {}

  public RectF(float l, float t, float r, float b) {
    set(l, t, r, b);
  }

  public RectF(RectF r) {
    set(r.left, r.top, r.right, r.bottom);
  }

  public RectF(Rect r) {
    set(r.left, r.top, r.right, r.bottom);
  }

  public void set(float l, float t, float r, float b) {
    left = l;
    top = t;
    right = r;
    bottom = b;
  }

  public float width() {
    return right - left;
  }

  public float height() {
    return bottom - top;
  }

  public boolean isEmpty() {
    return left >= right || top >= bottom;
  }
}
