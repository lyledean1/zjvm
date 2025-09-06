public class Fibonacci {
    public static void main(String[] args) {
        Printer printer = new Printer(0);
        
        int n = 10;
        printer.print("Fibonacci sequence:");
        
        for (int i = 0; i < n; i++) {
            printer.print(fibonacci(i));
        }
    }
    
    public static int fibonacci(int n) {
        if (n <= 1) {
            return n;
        }
        return fibonacci(n - 1) + fibonacci(n - 2);
    }
}