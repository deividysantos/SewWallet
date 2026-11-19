-- AlterTable
ALTER TABLE "Recurrence" ADD COLUMN     "withCounterpart" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN     "counterpartOfId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Transaction_counterpartOfId_key" ON "Transaction"("counterpartOfId");

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_counterpartOfId_fkey" FOREIGN KEY ("counterpartOfId") REFERENCES "Transaction"("id") ON DELETE CASCADE ON UPDATE CASCADE;

