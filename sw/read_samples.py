import csv

def read_samples_csv(path):

    indices = []
    values = []

    with open(path, "r") as file:

        reader = csv.DictReader(file)

        for row in reader:
            indices.append(int(row["index"]))
            values.append(float(row["value"]))

    return indices, values


if __name__ == "__main__":

    file_path = "../tests/samples.csv"

    indices, samples = read_samples_csv(file_path)

    print("Number of samples:", len(samples))
    print("First 10 samples:", samples[:10])
