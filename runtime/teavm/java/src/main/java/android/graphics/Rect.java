package android.graphics;
public class Rect {
 public int left,top,right,bottom;
 public Rect(){}public Rect(int l,int t,int r,int b){set(l,t,r,b);}public Rect(Rect r){set(r);}
 public void set(int l,int t,int r,int b){left=l;top=t;right=r;bottom=b;}public void set(Rect r){set(r.left,r.top,r.right,r.bottom);}
 public int width(){return right-left;}public int height(){return bottom-top;}public boolean isEmpty(){return left>=right||top>=bottom;}
 public void offset(int x,int y){left+=x;right+=x;top+=y;bottom+=y;}public boolean contains(int x,int y){return left<=x&&x<right&&top<=y&&y<bottom;}
 public String toString(){return "Rect("+left+", "+top+" - "+right+", "+bottom+")";}
}
