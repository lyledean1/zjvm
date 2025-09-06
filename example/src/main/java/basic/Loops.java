public class Loops {
    
    public static void main(String[] args) {
        System.out.println("For loop example:");
        forLoopExample();
        
        System.out.println("While loop example:");
        whileLoopExample();
    }
    
    public static void forLoopExample() {
        for (int i = 1; i <= 5; i++) {
            System.out.println("For loop iteration: " + i);
        }
        
        for (int j = 10; j >= 8; j--) {
            System.out.println("Countdown: " + j);
        }
    }
    
    public static void whileLoopExample() {
        int counter = 1;
        while (counter <= 3) {
            System.out.println("While loop iteration: " + counter);
            counter++;
        }
        
        int value = 20;
        while (value > 15) {
            System.out.println("Value is: " + value);
            value -= 2;
        }
    }
}