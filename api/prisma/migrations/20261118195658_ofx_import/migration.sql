-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN     "externalId" TEXT,
ADD COLUMN     "externalName" TEXT;

-- CreateIndex
CREATE INDEX "Transaction_cardId_externalId_idx" ON "Transaction"("cardId", "externalId");
