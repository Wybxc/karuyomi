package android.view;

import android.content.Context;

/** Layout state for the iframe host; WebView maps these dimensions to its viewport. */
public class View {
  private final Context context;
  private ViewGroup.LayoutParams layoutParams;
  private int measuredWidth, measuredHeight, left, top, right, bottom;

  public View(Context context) {
    this.context = context;
  }

  public Context getContext() {
    return context;
  }

  public ViewParent getParent() {
    return null;
  }

  public View getRootView() {
    throw new UnsupportedOperationException("Android view hierarchy is unsupported");
  }

  public final View findViewById(int id) {
    return findViewTraversal(id);
  }

  protected View findViewTraversal(int id) {
    throw new UnsupportedOperationException("Android view lookup is unsupported");
  }

  public void setLayoutParams(ViewGroup.LayoutParams params) {
    layoutParams = java.util.Objects.requireNonNull(params);
  }

  public ViewGroup.LayoutParams getLayoutParams() {
    return layoutParams;
  }

  public final void measure(int widthSpec, int heightSpec) {
    measuredWidth =
        MeasureSpec.getMode(widthSpec) == MeasureSpec.UNSPECIFIED
            ? 0
            : MeasureSpec.getSize(widthSpec);
    measuredHeight =
        MeasureSpec.getMode(heightSpec) == MeasureSpec.UNSPECIFIED
            ? 0
            : MeasureSpec.getSize(heightSpec);
  }

  public int getMeasuredWidth() {
    return measuredWidth;
  }

  public int getMeasuredHeight() {
    return measuredHeight;
  }

  public void layout(int left, int top, int right, int bottom) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  public int getLeft() {
    return left;
  }

  public int getTop() {
    return top;
  }

  public int getRight() {
    return right;
  }

  public int getBottom() {
    return bottom;
  }

  public int getWidth() {
    return right - left;
  }

  public int getHeight() {
    return bottom - top;
  }

  public static final class MeasureSpec {
    public static final int UNSPECIFIED = 0, EXACTLY = 0x40000000, AT_MOST = 0x80000000;

    public static int makeMeasureSpec(int size, int mode) {
      return (size & 0x3fffffff) | (mode & 0xc0000000);
    }

    public static int getMode(int spec) {
      return spec & 0xc0000000;
    }

    public static int getSize(int spec) {
      return spec & 0x3fffffff;
    }
  }
}
