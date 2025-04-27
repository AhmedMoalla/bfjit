import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

public class BrainfuckProgram {
    private static final List<Integer> bytes = new ArrayList<>();
    private static int head;

    public static void incHead(int count) {
        head += count;
        appendZerosToReachHead();
    }

    public static void decHead(int count) {
        if (head < count) {
            throw new RuntimeException("MemoryUnderflow");
        }
        head -= count;
    }

    public static void incAtHead(int count) {
        appendZerosToReachHead();
        Integer currentValue = bytes.get(head);
        bytes.set(head, currentValue + count);
    }

    public static void decAtHead(int count) {
        appendZerosToReachHead();
        Integer currentValue = bytes.get(head);
        bytes.set(head, currentValue - count);
    }

    public static Integer getAtHead() {
        if (head >= bytes.size()) {
            return null;
        }

        return bytes.get(head);
    }

    public static void setAtHead(int value) {
        appendZerosToReachHead();
        bytes.set(head, value);
    }

    private static void appendZerosToReachHead() {
        while (head >= bytes.size()) {
            bytes.add(0);
        }
    }

    public static void outputAtHead(int count) {
        headValue = getAtHead();
        if (headValue != null) {
            for (int i = 0; i < count; i++) {
                System.out.print((char) headValue.intValue());
            }
        }
    }

    public static void inputAtHead(int count) throws IOException {
        for (int i = 0; i < count; i++) {
            if ((nextIn = System.in.read()) != -1) {
                setAtHead(nextIn);
            }
        }
    }

    public static boolean headNotZero() {
        return (headValue = getAtHead()) != null && headValue != 0;
    }

    private static Integer headValue, nextIn;

    public static void main(String[] args) throws IOException {
        setAtHead(0);
        incAtHead(1);
        decAtHead(1);
        decHead(1);
        incHead(1);
        inputAtHead(1);
        outputAtHead(1);
        while (headNotZero()) {}
    }
}
