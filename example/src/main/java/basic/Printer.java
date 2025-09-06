public class Printer {
    public int value;

    Printer(int value) {
        this.value = value;
    }

    public void print(String val) {
        System.out.println(this.value);
        System.out.println(val);
    }

    public void print(int val) {
        System.out.println(val);
    }

    public void print(boolean val, boolean cmp) {
        if (val) {
            System.out.println("this is true");
        }
        if (!val) {
            System.out.println("this is false");
        }
        if (val == cmp) {
            System.out.println("comparing is true");
        }
        if (val != cmp) {
            System.out.println("comparing is false");
        }
    }
}